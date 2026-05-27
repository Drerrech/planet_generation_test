#@tool

extends Node

const print_debug = false

const chunk_scene := preload("res://chunks/default_chunk/default_chunk.tscn")

# NOTE: MUST BE THE SAME AS EXECUTABLE
const NUM_CHUNKS_SIDE = Vector3i(32, 32, 32)
const NUM_CHUNKS = NUM_CHUNKS_SIDE.x * NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z
const CHUNK_SIZE = Vector3(16.0, 16.0, 16.0)

const CHUNK_SIDE_SIZE = 17  # must match CHUNK_SIDE_SIZE in C

const _chunk_shader := preload("res://planets/test_planet/shaders/test_shader.gdshader")
var _chunk_material: ShaderMaterial

var c_server: ChunkServer

# Accumulated client-side changes per chunk, cleared after reliable flush
var _dirty_chunks: Dictionary = {}  # chunk_id -> {idx: val, ...}
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

func add_all_chunks() -> void:
	if print_debug:
		print("[chunks] adding ", NUM_CHUNKS, " chunks...")
	var id = 0
	for x in range(NUM_CHUNKS_SIDE.x):
		for y in range(NUM_CHUNKS_SIDE.y):
			for z in range(NUM_CHUNKS_SIDE.z):
				var chunk_instance = chunk_scene.instantiate()
				chunk_instance.chunk_id = id
				chunk_instance.position = (Vector3(x, y, z) - 0.5*NUM_CHUNKS_SIDE) * CHUNK_SIZE
				add_child(chunk_instance)
				unload_chunk(id)
				id += 1
	if print_debug:
		print("[chunks] all chunks added")

func load_chunk(chunk_id: int, load_collision: bool = false) -> void:
	if print_debug:
		print("Children count:", get_child_count())
		print("[chunks] loading chunk ", chunk_id, "...")

	var chunk_instance = get_child(chunk_id)

	if load_collision:
		var mesh = chunk_instance.mesh_instance.mesh
		if mesh and mesh.get_surface_count() > 0:
			WorkerThreadPool.add_task(func():
				chunk_instance.collision_shape.set_deferred("shape", mesh.create_trimesh_shape())
			)
		return

	chunk_instance.load_chunk()

	if not multiplayer.is_server():
		request_bin_data.rpc_id(1, chunk_id)
		return

	_load_chunk_delta(chunk_id)
	_generate_and_apply_mesh(chunk_id)


func _generate_and_apply_mesh(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	var result = c_server.generate_chunk(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z
	)
	chunk_instance.point_values = result.point_values
	chunk_instance.mesh_instance.mesh = result.mesh
	chunk_instance.mesh_instance.material_override = _chunk_material


func _update_chunk_mesh(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	var t0 = Time.get_ticks_usec() if print_debug else 0
	var mesh = c_server.update_chunk(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z,
		chunk_instance.delta
	)
	chunk_instance.mesh_instance.mesh = mesh
	if mesh.get_surface_count() > 0:
		WorkerThreadPool.add_task(func():
			chunk_instance.collision_shape.set_deferred("shape", mesh.create_trimesh_shape())
		)
	else:
		chunk_instance.collision_shape.shape = null
	if print_debug:
		print("update_chunk: %.2fms" % [(Time.get_ticks_usec()-t0)/1000.0])


# --- bin file helpers ---

func _load_chunk_delta(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	chunk_instance.delta = {}
	var path = "user://player_delta/test_planet/%d.bin" % chunk_id
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	while f.get_position() < f.get_length():
		var idx = f.get_32()
		var val = f.get_float()
		chunk_instance.delta[idx] = val
	f.close()

func _write_chunk_bin(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	var dir = "user://player_delta/test_planet"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f = FileAccess.open("%s/%d.bin" % [dir, chunk_id], FileAccess.WRITE)
	for idx in chunk_instance.delta:
		f.store_32(idx)
		f.store_float(chunk_instance.delta[idx])
	f.close()


# --- delta serialization ---

func _encode_deltas(all_deltas: Dictionary) -> PackedByteArray:
	var total = 4
	for chunk_id in all_deltas:
		total += 8 + all_deltas[chunk_id].size() * 8
	var buf := PackedByteArray()
	buf.resize(total)
	var offset = 0
	buf.encode_s32(offset, all_deltas.size())
	offset += 4
	for chunk_id in all_deltas:
		var chunk_delta = all_deltas[chunk_id]
		buf.encode_s32(offset, chunk_id)
		buf.encode_s32(offset + 4, chunk_delta.size())
		offset += 8
		for idx in chunk_delta:
			buf.encode_s32(offset, idx)
			buf.encode_float(offset + 4, chunk_delta[idx])
			offset += 8
	return buf

func _decode_deltas(buf: PackedByteArray) -> Dictionary:
	var all_deltas := {}
	var offset = 0
	var num_chunks = buf.decode_s32(offset)
	offset += 4
	for _c in range(num_chunks):
		var chunk_id = buf.decode_s32(offset)
		var num_entries = buf.decode_s32(offset + 4)
		offset += 8
		var chunk_delta := {}
		for _e in range(num_entries):
			chunk_delta[buf.decode_s32(offset)] = buf.decode_float(offset + 4)
			offset += 8
		all_deltas[chunk_id] = chunk_delta
	return all_deltas


# --- chunk change RPCs ---

func on_chunk_changed(chunk_id: int, incoming_delta: Dictionary) -> void:
	if not multiplayer.is_server():
		# Accumulate — soil_gun calls send_dirty() once per shot to flush all at once
		if chunk_id not in _dirty_chunks:
			_dirty_chunks[chunk_id] = {}
		var chunk_instance = get_child(chunk_id)
		for idx in incoming_delta:
			_dirty_chunks[chunk_id][idx] = incoming_delta[idx]
			chunk_instance.delta[idx] = incoming_delta[idx]
		_update_chunk_mesh(chunk_id)
		return
	# Host digging: defer bin write to flush_pending
	_host_dirty_chunk_ids[chunk_id] = true
	_server_apply_all_chunks({chunk_id: incoming_delta}, false)

# Called by soil_gun after every shot.
# Sends all dirty chunks in ONE unreliable packet — atomic UDP delivery means
# boundary-adjacent chunks either both arrive or neither does, never one without the other.
func send_dirty() -> void:
	if multiplayer.is_server() or _dirty_chunks.is_empty():
		return
	_request_chunk_changes.rpc_id(1, _encode_deltas(_dirty_chunks))

# Called by soil_gun when the dig button is released.
func flush_pending() -> void:
	if multiplayer.is_server():
		for chunk_id in _host_dirty_chunk_ids:
			_write_chunk_bin(chunk_id)
		_host_dirty_chunk_ids.clear()
		return
	if not _dirty_chunks.is_empty():
		_flush_chunk_changes.rpc_id(1, _encode_deltas(_dirty_chunks))
	_dirty_chunks.clear()

# Unreliable: one packet per shot with all affected chunks bundled together.
# Newer packets supersede older ones so there is no queue buildup on the host.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _request_chunk_changes(data: PackedByteArray) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var all_deltas = _decode_deltas(data)
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
	_server_apply_all_chunks(all_deltas, false, sender)

# Reliable: sent once on button release, guarantees final state is written to disk.
@rpc("any_peer", "call_remote", "reliable")
func _flush_chunk_changes(data: PackedByteArray) -> void:
	var sender = multiplayer.get_remote_sender_id()
	var all_deltas = _decode_deltas(data)
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
	_server_apply_all_chunks(all_deltas, true, sender)

func _server_apply_all_chunks(all_deltas: Dictionary, persist: bool, exclude_peer: int = 0) -> void:
	for chunk_id in all_deltas:
		if persist:
			_write_chunk_bin(chunk_id)
		_update_chunk_mesh(chunk_id)
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			if idx < chunk_instance.point_values.size():
				chunk_instance.point_values[idx] = all_deltas[chunk_id][idx]
	var encoded = _encode_deltas(all_deltas)
	for peer_id in multiplayer.get_peers():
		if peer_id == exclude_peer:
			continue
		if persist:
			_receive_chunk_changes_persist.rpc_id(peer_id, encoded)
		else:
			_receive_chunk_changes.rpc_id(peer_id, encoded)

@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_chunk_changes(data: PackedByteArray) -> void:
	var all_deltas = _decode_deltas(data)
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
			if idx < chunk_instance.point_values.size():
				chunk_instance.point_values[idx] = all_deltas[chunk_id][idx]
		_update_chunk_mesh(chunk_id)

@rpc("authority", "call_remote", "reliable")
func _receive_chunk_changes_persist(data: PackedByteArray) -> void:
	var all_deltas = _decode_deltas(data)
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
			if idx < chunk_instance.point_values.size():
				chunk_instance.point_values[idx] = all_deltas[chunk_id][idx]
		_write_chunk_bin(chunk_id)
		_update_chunk_mesh(chunk_id)


# --- bin data RPCs (used on chunk load) ---

@rpc("any_peer", "call_remote", "reliable")
func request_bin_data(chunk_id: int) -> void:
	if print_debug:
		print("[chunks] request_bin_data received for chunk ", chunk_id, " from peer ", multiplayer.get_remote_sender_id())
	var chunk_instance = get_child(chunk_id)
	var data := PackedByteArray()
	if chunk_instance.loaded:
		var delta = chunk_instance.delta
		data.resize(delta.size() * 8)
		var offset = 0
		for idx in delta:
			data.encode_s32(offset, idx)
			data.encode_float(offset + 4, delta[idx])
			offset += 8
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
	var chunk_instance = get_child(chunk_id)
	chunk_instance.delta = {}
	if data.size() > 0:
		var dir = "user://player_delta/test_planet"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f = FileAccess.open("%s/%d.bin" % [dir, chunk_id], FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
		# populate in-memory delta from received bytes
		var offset = 0
		while offset + 8 <= data.size():
			var idx = data.decode_s32(offset)
			var val = data.decode_float(offset + 4)
			chunk_instance.delta[idx] = val
			offset += 8
	_generate_and_apply_mesh(chunk_id)


func unload_chunk(chunk_id: int) -> void:
	if print_debug:
		print("[chunks] unloading chunk ", chunk_id)

	var chunk_instance = get_child(chunk_id)
	chunk_instance.unload_chunk()
	chunk_instance.mesh_instance.mesh = null
	chunk_instance.collision_shape.shape = null

	c_server.free_chunk(chunk_id)

	if print_debug:
		print("[chunks] chunk ", chunk_id, " unloaded")
