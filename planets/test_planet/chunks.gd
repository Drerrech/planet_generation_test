#@tool

extends Node

const print_debug = false

const chunk_scene := preload("res://chunks/default_chunk/default_chunk.tscn")

# NOTE: MUST BE THE SAME AS EXECUTABLE
const NUM_CHUNKS_SIDE = Vector3i(64, 64, 64)
const NUM_CHUNKS = NUM_CHUNKS_SIDE.x * NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z
const CHUNK_SIZE = Vector3(16.0, 16.0, 16.0)

const CHUNK_SIDE_SIZE = 17  # must match CHUNK_SIDE_SIZE in C

const _chunk_shader := preload("res://planets/test_planet/shaders/test_shader.gdshader")
var _chunk_material: ShaderMaterial

var c_server: ChunkServer

# Reference counting for lazy chunk nodes. Chunks only exist as nodes while at
# least one loader wants them. Nodes are named str(id) and looked up by name.
var _mesh_refs: Dictionary = {}  # chunk_id -> int (loaders wanting the mesh)
var _col_refs: Dictionary = {}   # chunk_id -> int (loaders wanting collision)

# Accumulated client-side changes per chunk, cleared after reliable flush
var _dirty_chunks: Dictionary = {}       # chunk_id -> {idx: val}
var _dirty_chunk_types: Dictionary = {}  # chunk_id -> {idx: type}
# Server-side: chunks dug by host this session, flushed to disk on button release
var _host_dirty_chunk_ids: Dictionary = {}  # chunk_id -> true

func init() -> void:
	c_server = ChunkServer.new()
	c_server.set_user_dir(ProjectSettings.globalize_path("user://"))
	_chunk_material = ShaderMaterial.new()
	_chunk_material.shader = _chunk_shader

func _exit_tree() -> void:
	if c_server:
		c_server.free()
		c_server = null


# --- lookup / addressing ---

func get_chunk(chunk_id: int):
	return get_node_or_null(str(chunk_id))

func _chunk_local_position(chunk_id: int) -> Vector3:
	var x = chunk_id / (NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z)
	var y = (chunk_id / NUM_CHUNKS_SIDE.z) % NUM_CHUNKS_SIDE.y
	var z = chunk_id % NUM_CHUNKS_SIDE.z
	return (Vector3(x, y, z) - 0.5 * Vector3(NUM_CHUNKS_SIDE)) * CHUNK_SIZE


# --- ref-counted load / unload (called by chunk loaders) ---

func acquire_mesh(chunk_id: int) -> void:
	_mesh_refs[chunk_id] = _mesh_refs.get(chunk_id, 0) + 1
	if _mesh_refs[chunk_id] == 1:
		_load_mesh(chunk_id)

func release_mesh(chunk_id: int) -> void:
	if chunk_id not in _mesh_refs:
		return
	_mesh_refs[chunk_id] -= 1
	if _mesh_refs[chunk_id] <= 0:
		_mesh_refs.erase(chunk_id)
		_col_refs.erase(chunk_id)  # collision can't outlive its mesh node
		_free_chunk_node(chunk_id)

func acquire_collision(chunk_id: int) -> void:
	_col_refs[chunk_id] = _col_refs.get(chunk_id, 0) + 1
	if _col_refs[chunk_id] == 1:
		_refresh_collision(chunk_id)

func release_collision(chunk_id: int) -> void:
	if chunk_id not in _col_refs:
		return
	_col_refs[chunk_id] -= 1
	if _col_refs[chunk_id] <= 0:
		_col_refs.erase(chunk_id)
		var chunk_instance = get_chunk(chunk_id)
		if chunk_instance:
			chunk_instance.collision_shape.shape = null


func _load_mesh(chunk_id: int) -> void:
	if get_chunk(chunk_id):
		return  # already instantiated
	var chunk_instance = chunk_scene.instantiate()
	chunk_instance.chunk_id = chunk_id
	chunk_instance.name = str(chunk_id)
	chunk_instance.position = _chunk_local_position(chunk_id)
	add_child(chunk_instance)
	chunk_instance.load_chunk()

	if not multiplayer.is_server():
		request_bin_data.rpc_id(1, chunk_id)
		return

	_load_chunk_delta(chunk_id)
	_generate_and_apply_mesh(chunk_id)

func _free_chunk_node(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if chunk_instance:
		chunk_instance.unload_chunk()
		chunk_instance.mesh_instance.mesh = null
		chunk_instance.collision_shape.shape = null
		# rename so a same-frame re-acquire doesn't find the freeing node
		chunk_instance.name = str(chunk_id) + "_freeing"
		chunk_instance.queue_free()
	c_server.free_chunk(chunk_id)

# Builds (or rebuilds) the collision shape on a worker thread if collision is
# wanted and a mesh exists. Called on collision acquire and on every mesh apply,
# so client chunks pick up collision once their mesh arrives.
func _refresh_collision(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if not chunk_instance:
		return
	if _col_refs.get(chunk_id, 0) <= 0:
		chunk_instance.collision_shape.shape = null
		return
	var mesh = chunk_instance.mesh_instance.mesh
	if mesh and mesh.get_surface_count() > 0:
		WorkerThreadPool.add_task(func():
			chunk_instance.collision_shape.set_deferred("shape", mesh.create_trimesh_shape())
		)
	else:
		chunk_instance.collision_shape.shape = null


func _generate_and_apply_mesh(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if not chunk_instance:
		return
	var result = c_server.generate_chunk(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z
	)
	chunk_instance.point_values = result.point_values
	chunk_instance.mesh_instance.mesh = result.mesh
	chunk_instance.mesh_instance.material_override = _chunk_material
	_refresh_collision(chunk_id)


func _update_chunk_mesh(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if not chunk_instance:
		return
	var t0 = Time.get_ticks_usec() if print_debug else 0
	var mesh = c_server.update_chunk(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z,
		chunk_instance.delta,
		chunk_instance.delta_type
	)
	chunk_instance.mesh_instance.mesh = mesh
	_refresh_collision(chunk_id)
	if print_debug:
		print("update_chunk: %.2fms" % [(Time.get_ticks_usec()-t0)/1000.0])


# --- bin file helpers ---
# Binary format per entry: [uint16 idx][float16 value][uint8 type] = 5 bytes

func _load_chunk_delta(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	chunk_instance.delta = {}
	chunk_instance.delta_type = {}
	var path = "user://player_delta/test_planet/%d.bin" % chunk_id
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	while f.get_position() + 5 <= f.get_length():
		var idx = f.get_16()
		var val_bytes = f.get_buffer(2)
		var val = val_bytes.decode_half(0)
		var type = f.get_8()
		chunk_instance.delta[idx] = val
		if type != 0:
			chunk_instance.delta_type[idx] = type
	f.close()

func _write_chunk_bin(chunk_id: int) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if not chunk_instance:
		return
	var dir = "user://player_delta/test_planet"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f = FileAccess.open("%s/%d.bin" % [dir, chunk_id], FileAccess.WRITE)
	var val_buf := PackedByteArray()
	val_buf.resize(2)
	for idx in chunk_instance.delta:
		f.store_16(idx)
		val_buf.encode_half(0, chunk_instance.delta[idx])
		f.store_buffer(val_buf)
		f.store_8(chunk_instance.delta_type.get(idx, 0))
	f.close()

# Merge a delta into a chunk's bin file without a node (chunk not loaded here).
# The bin file is authoritative for unloaded chunks.
func _merge_delta_to_bin(chunk_id: int, delta: Dictionary, types: Dictionary) -> void:
	var dir = "user://player_delta/test_planet"
	var path = "%s/%d.bin" % [dir, chunk_id]
	var gpath = ProjectSettings.globalize_path(path)
	var merged: Dictionary = {}       # idx -> val
	var merged_types: Dictionary = {}  # idx -> type
	if FileAccess.file_exists(path):
		var rf = FileAccess.open(path, FileAccess.READ)
		while rf.get_position() + 5 <= rf.get_length():
			var idx = rf.get_16()
			var vb = rf.get_buffer(2)
			merged[idx] = vb.decode_half(0)
			var t = rf.get_8()
			if t != 0:
				merged_types[idx] = t
		rf.close()
	for idx in delta:
		merged[idx] = delta[idx]
	for idx in types:
		if types[idx] == 0:
			merged_types.erase(idx)
		else:
			merged_types[idx] = types[idx]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f = FileAccess.open(path, FileAccess.WRITE)
	var val_buf := PackedByteArray()
	val_buf.resize(2)
	for idx in merged:
		f.store_16(idx)
		val_buf.encode_half(0, merged[idx])
		f.store_buffer(val_buf)
		f.store_8(merged_types.get(idx, 0))
	f.close()


# --- delta serialization ---
# RPC format: [int32 num_chunks] then per chunk: [int32 chunk_id][int32 count][entries...]
# Each entry: [uint16 idx][float16 value][uint8 type] = 5 bytes

func _encode_deltas(all_deltas: Dictionary, all_types: Dictionary) -> PackedByteArray:
	var total = 4
	for chunk_id in all_deltas:
		total += 8 + all_deltas[chunk_id].size() * 5
	var buf := PackedByteArray()
	buf.resize(total)
	var offset = 0
	buf.encode_s32(offset, all_deltas.size())
	offset += 4
	for chunk_id in all_deltas:
		var chunk_delta = all_deltas[chunk_id]
		var chunk_types = all_types.get(chunk_id, {})
		buf.encode_s32(offset, chunk_id)
		buf.encode_s32(offset + 4, chunk_delta.size())
		offset += 8
		for idx in chunk_delta:
			buf.encode_u16(offset, idx)
			buf.encode_half(offset + 2, chunk_delta[idx])
			buf[offset + 4] = chunk_types.get(idx, 0)
			offset += 5
	return buf

func _decode_deltas(buf: PackedByteArray) -> Array:
	var all_deltas := {}
	var all_types := {}
	var offset = 0
	var num_chunks = buf.decode_s32(offset)
	offset += 4
	for _c in range(num_chunks):
		var chunk_id = buf.decode_s32(offset)
		var num_entries = buf.decode_s32(offset + 4)
		offset += 8
		var chunk_delta := {}
		var chunk_types := {}
		for _e in range(num_entries):
			var idx = buf.decode_u16(offset)
			var val = buf.decode_half(offset + 2)
			var type = buf[offset + 4]
			chunk_delta[idx] = val
			if type != 0:
				chunk_types[idx] = type
			offset += 5
		all_deltas[chunk_id] = chunk_delta
		all_types[chunk_id] = chunk_types
	return [all_deltas, all_types]


# Applies a remote delta to local storage. If the chunk is loaded here it updates
# the node + mesh; if not, it merges into the authoritative bin file.
func _apply_remote_delta(chunk_id: int, delta: Dictionary, types: Dictionary, persist: bool) -> void:
	var chunk_instance = get_chunk(chunk_id)
	if chunk_instance:
		for idx in delta:
			chunk_instance.delta[idx] = delta[idx]
			if idx < chunk_instance.point_values.size():
				chunk_instance.point_values[idx] = delta[idx]
		for idx in types:
			if types[idx] == 0:
				chunk_instance.delta_type.erase(idx)
			else:
				chunk_instance.delta_type[idx] = types[idx]
		if persist:
			_write_chunk_bin(chunk_id)
		_update_chunk_mesh(chunk_id)
	else:
		# not loaded here: bin file is the source of truth, always persist
		_merge_delta_to_bin(chunk_id, delta, types)


# --- chunk change RPCs ---

func on_chunk_changed(chunk_id: int, incoming_delta: Dictionary, incoming_delta_type: Dictionary) -> void:
	if not multiplayer.is_server():
		# Accumulate — soil_gun calls send_dirty() once per shot to flush all at once
		if chunk_id not in _dirty_chunks:
			_dirty_chunks[chunk_id] = {}
		if chunk_id not in _dirty_chunk_types:
			_dirty_chunk_types[chunk_id] = {}
		var chunk_instance = get_chunk(chunk_id)
		for idx in incoming_delta:
			_dirty_chunks[chunk_id][idx] = incoming_delta[idx]
			if chunk_instance:
				chunk_instance.delta[idx] = incoming_delta[idx]
		for idx in incoming_delta_type:
			_dirty_chunk_types[chunk_id][idx] = incoming_delta_type[idx]
			if chunk_instance:
				if incoming_delta_type[idx] == 0:
					chunk_instance.delta_type.erase(idx)
				else:
					chunk_instance.delta_type[idx] = incoming_delta_type[idx]
		_update_chunk_mesh(chunk_id)
		return
	# Host digging: defer bin write to flush_pending
	_host_dirty_chunk_ids[chunk_id] = true
	_server_apply_all_chunks({chunk_id: incoming_delta}, {chunk_id: incoming_delta_type}, false)

# Called by soil_gun after every shot.
# Sends all dirty chunks in ONE unreliable packet.
func send_dirty() -> void:
	if multiplayer.is_server() or _dirty_chunks.is_empty():
		return
	_request_chunk_changes.rpc_id(1, _encode_deltas(_dirty_chunks, _dirty_chunk_types))

# Called by soil_gun when the dig button is released.
func flush_pending() -> void:
	if multiplayer.is_server():
		for chunk_id in _host_dirty_chunk_ids:
			_write_chunk_bin(chunk_id)
		_host_dirty_chunk_ids.clear()
		return
	if not _dirty_chunks.is_empty():
		_flush_chunk_changes.rpc_id(1, _encode_deltas(_dirty_chunks, _dirty_chunk_types))
	_dirty_chunks.clear()
	_dirty_chunk_types.clear()

# Unreliable: one packet per shot with all affected chunks bundled together.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _request_chunk_changes(data: PackedByteArray) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var decoded = _decode_deltas(data)
	_server_apply_all_chunks(decoded[0], decoded[1], false, sender)

# Reliable: sent once on button release, guarantees final state is written to disk.
@rpc("any_peer", "call_remote", "reliable")
func _flush_chunk_changes(data: PackedByteArray) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var decoded = _decode_deltas(data)
	_server_apply_all_chunks(decoded[0], decoded[1], true, sender)

func _server_apply_all_chunks(all_deltas: Dictionary, all_types: Dictionary, persist: bool, exclude_peer: int = 0) -> void:
	for chunk_id in all_deltas:
		_apply_remote_delta(chunk_id, all_deltas[chunk_id], all_types.get(chunk_id, {}), persist)
	var encoded = _encode_deltas(all_deltas, all_types)
	for peer_id in multiplayer.get_peers():
		if peer_id == exclude_peer:
			continue
		if persist:
			_receive_chunk_changes_persist.rpc_id(peer_id, encoded)
		else:
			_receive_chunk_changes.rpc_id(peer_id, encoded)

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_chunk_changes(data: PackedByteArray) -> void:
	var decoded = _decode_deltas(data)
	var all_deltas = decoded[0]
	var all_types = decoded[1]
	for chunk_id in all_deltas:
		_apply_remote_delta(chunk_id, all_deltas[chunk_id], all_types.get(chunk_id, {}), false)

@rpc("authority", "call_remote", "reliable")
func _receive_chunk_changes_persist(data: PackedByteArray) -> void:
	var decoded = _decode_deltas(data)
	var all_deltas = decoded[0]
	var all_types = decoded[1]
	for chunk_id in all_deltas:
		_apply_remote_delta(chunk_id, all_deltas[chunk_id], all_types.get(chunk_id, {}), true)


# --- bin data RPCs (used on chunk load) ---

@rpc("any_peer", "call_remote", "reliable")
func request_bin_data(chunk_id: int) -> void:
	if print_debug:
		print("[chunks] request_bin_data received for chunk ", chunk_id, " from peer ", multiplayer.get_remote_sender_id())
	var chunk_instance = get_chunk(chunk_id)
	var data := PackedByteArray()
	if chunk_instance and chunk_instance.loaded:
		var delta = chunk_instance.delta
		var delta_type = chunk_instance.delta_type
		data.resize(delta.size() * 5)
		var offset = 0
		for idx in delta:
			data.encode_u16(offset, idx)
			data.encode_half(offset + 2, delta[idx])
			data[offset + 4] = delta_type.get(idx, 0)
			offset += 5
	else:
		var path = "user://player_delta/test_planet/%d.bin" % chunk_id
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			data = f.get_buffer(f.get_length())
			f.close()
	var sender_id = multiplayer.get_remote_sender_id()
	receive_bin_data.rpc_id(sender_id, chunk_id, data)

@rpc("authority", "call_remote", "reliable")
func receive_bin_data(chunk_id: int, data: PackedByteArray) -> void:
	if print_debug:
		print("[chunks] receive_bin_data received for chunk ", chunk_id, " data size: ", data.size())
	var chunk_instance = get_chunk(chunk_id)
	if not chunk_instance:
		# chunk was unloaded before the reply arrived
		return
	chunk_instance.delta = {}
	chunk_instance.delta_type = {}
	if data.size() > 0:
		var dir = "user://player_delta/test_planet"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f = FileAccess.open("%s/%d.bin" % [dir, chunk_id], FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
		var offset = 0
		while offset + 5 <= data.size():
			var idx = data.decode_u16(offset)
			var val = data.decode_half(offset + 2)
			var type = data[offset + 4]
			chunk_instance.delta[idx] = val
			if type != 0:
				chunk_instance.delta_type[idx] = type
			offset += 5
	_generate_and_apply_mesh(chunk_id)
