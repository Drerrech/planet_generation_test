#@tool

extends Node

const print_debug = false

const chunk_scene := preload("res://chunks/default_chunk/default_chunk.tscn")

# NOTE: MUST BE THE SAME AS EXECUTABLE
const NUM_CHUNKS_SIDE = Vector3i(16, 16, 16) #Vector3i(32, 32, 32)
const NUM_CHUNKS = NUM_CHUNKS_SIDE.x * NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z
const CHUNK_SIZE = Vector3(32.0, 32.0, 32.0) # Vector3(16.0, 16.0, 16.0)

const REQ_GENERATE = 1
const REQ_DELETE   = 2
const REQ_UPDATE   = 3
const VERTEX_SIZE  = 3 * 4  # 3 floats * 4 bytes
const CHUNK_SIDE_SIZE = 33  # must match CHUNK_SIDE_SIZE in C
const CHUNK_ARRAY_SIZE = CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE

var socket := StreamPeerTCP.new()
var pid: int = -1

# Accumulated client-side changes per chunk, cleared after reliable flush
var _dirty_chunks: Dictionary = {}  # chunk_id -> {idx: val, ...}

# NOTE: port is hardcoded per role — 8999 for host, 9080 for client.
# This only supports one host + one client on the same machine.
# Fix: use a GameState variable or dynamic port negotiation to support more instances.
var _c_server_port: int:
	get: return 9080 if not GameState.is_server else 8999

func init() -> void:
	if print_debug:
		print("[chunks] spawning server process...")
	var exe_path = ProjectSettings.globalize_path("res://chunk_executables/test_server")
	var user_dir = ProjectSettings.globalize_path("user://")
	pid = OS.create_process(exe_path, [user_dir, str(_c_server_port)])

	await get_tree().create_timer(0.2).timeout

	if print_debug:
		print("[chunks] connecting to server...")
	var err = socket.connect_to_host("127.0.0.1", _c_server_port)
	if err != OK:
		if print_debug:
			print("[chunks] connect_to_host failed: ", err)
		return

	while true:
		socket.poll()
		var status = socket.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			break
		if status == StreamPeerTCP.STATUS_ERROR:
			if print_debug:
				print("[chunks] socket connection failed")
			return
		await get_tree().process_frame

	if print_debug:
		print("[chunks] connected to server")

func _exit_tree():
	if print_debug:
		print("[chunks] disconnecting and killing server process...")
	socket.disconnect_from_host()
	if pid != -1:
		OS.kill(pid)
		pid = -1
	if print_debug:
		print("[chunks] server killed")

func _recv_vertices() -> PackedVector3Array:
	var deadline = Time.get_ticks_msec() + 5000
	while socket.get_available_bytes() < 4:
		socket.poll()
		if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("[chunks] ERROR: socket disconnected waiting for vertex count")
			return PackedVector3Array()
		if Time.get_ticks_msec() > deadline:
			print("[chunks] ERROR: timed out waiting for vertex count")
			return PackedVector3Array()
	var vertex_count = socket.get_32()

	var total_bytes = vertex_count * VERTEX_SIZE
	var bytes := PackedByteArray()
	deadline = Time.get_ticks_msec() + 10000
	while bytes.size() < total_bytes:
		socket.poll()
		if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("[chunks] ERROR: socket disconnected waiting for vertex data")
			return PackedVector3Array()
		if Time.get_ticks_msec() > deadline:
			print("[chunks] ERROR: timed out waiting for vertex data")
			return PackedVector3Array()
		var available = socket.get_available_bytes()
		if available > 0:
			var to_read = min(available, total_bytes - bytes.size())
			var result = socket.get_data(to_read)
			if result[0] != OK:
				if print_debug:
					print("[chunks] ERROR: get_data failed: ", result[0])
				return PackedVector3Array()
			bytes.append_array(result[1])
			deadline = Time.get_ticks_msec() + 10000

	var verts := PackedVector3Array()
	verts.resize(vertex_count)
	for i in range(vertex_count):
		var offset = i * VERTEX_SIZE
		verts[i] = Vector3(
			bytes.decode_float(offset),
			bytes.decode_float(offset + 4),
			bytes.decode_float(offset + 8)
		)
	return verts


func request_generate(chunk_id: int, x: float, y: float, z: float) -> Dictionary:
	if print_debug:
		print("[chunks] requesting generation for chunk ", chunk_id, " at (", x, ", ", y, ", ", z, ")")

	socket.put_u8(REQ_GENERATE)
	socket.put_32(chunk_id)
	socket.put_float(x)
	socket.put_float(y)
	socket.put_float(z)
	socket.poll()

	var verts = _recv_vertices()
	if print_debug:
		print("[chunks] chunk ", chunk_id, " received ", verts.size(), " vertices")

	# read full voxel array (only sent on initial load)
	var array_total_bytes = CHUNK_ARRAY_SIZE * 4
	var array_bytes := PackedByteArray()
	var deadline = Time.get_ticks_msec() + 10000
	while array_bytes.size() < array_total_bytes:
		socket.poll()
		if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("[chunks] ERROR: socket disconnected waiting for point values")
			return {"vertices": verts, "point_values": PackedFloat32Array()}
		if Time.get_ticks_msec() > deadline:
			print("[chunks] ERROR: timed out waiting for point values")
			return {"vertices": verts, "point_values": PackedFloat32Array()}
		var available = socket.get_available_bytes()
		if available > 0:
			var to_read = min(available, array_total_bytes - array_bytes.size())
			var result = socket.get_data(to_read)
			if result[0] != OK:
				return {"vertices": verts, "point_values": PackedFloat32Array()}
			array_bytes.append_array(result[1])
			deadline = Time.get_ticks_msec() + 10000

	var point_values := PackedFloat32Array()
	point_values.resize(CHUNK_ARRAY_SIZE)
	for i in range(CHUNK_ARRAY_SIZE):
		point_values[i] = array_bytes.decode_float(i * 4)

	return {"vertices": verts, "point_values": point_values}


func request_update(chunk_id: int, x: float, y: float, z: float) -> PackedVector3Array:
	if print_debug:
		print("[chunks] requesting update for chunk ", chunk_id)

	var t0 = Time.get_ticks_msec()
	socket.put_u8(REQ_UPDATE)
	socket.put_32(chunk_id)
	socket.put_float(x)
	socket.put_float(y)
	socket.put_float(z)
	socket.poll()

	var verts = _recv_vertices()
	print("[chunks] request_update chunk %d: %d ms total round-trip" % [chunk_id, Time.get_ticks_msec() - t0])
	return verts

func build_mesh(verts: PackedVector3Array) -> ArrayMesh:
	if print_debug:
		print("[chunks] building mesh with ", verts.size(), " vertices")
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		st.add_vertex(v)

	st.generate_normals()
	st.index()

	var mesh = st.commit()
	if print_debug:
		print("[chunks] mesh built")
	return mesh


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

func load_chunk(chunk_id: int) -> void:
	if print_debug:
		print("Children count:", get_child_count())
		print("[chunks] loading chunk ", chunk_id, "...")

	var chunk_instance = get_child(chunk_id)
	chunk_instance.load_chunk()

	if not multiplayer.is_server():
		request_bin_data.rpc_id(1, chunk_id)
		return

	_load_chunk_delta(chunk_id)
	_generate_and_apply_mesh(chunk_id)


func _apply_mesh(chunk_id: int, raw_vertices: PackedVector3Array) -> void:
	var chunk_instance = get_child(chunk_id)
	var mesh = build_mesh(raw_vertices)
	chunk_instance.mesh_instance.mesh = mesh

	var test_shader = ShaderMaterial.new()
	test_shader.shader = preload("res://planets/test_planet/shaders/test_shader.gdshader")
	chunk_instance.mesh_instance.material_override = test_shader

	if mesh.get_surface_count() > 0:
		chunk_instance.collision_shape.shape = mesh.create_trimesh_shape()


func _generate_and_apply_mesh(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	var result = request_generate(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z
	)
	chunk_instance.point_values = result.point_values
	if print_debug:
		print("[chunks] _generate_and_apply_mesh chunk ", chunk_id, " got ", result.vertices.size(), " vertices")
	_apply_mesh(chunk_id, result.vertices)


func _update_chunk_mesh(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)
	var raw_vertices = request_update(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z
	)
	if print_debug:
		print("[chunks] _update_chunk_mesh chunk ", chunk_id, " got ", raw_vertices.size(), " vertices")
	_apply_mesh(chunk_id, raw_vertices)


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


# --- chunk change RPCs ---

func on_chunk_changed(chunk_id: int, incoming_delta: Dictionary) -> void:
	if not multiplayer.is_server():
		# Accumulate — soil_gun calls send_dirty() once per shot to flush all at once
		if chunk_id not in _dirty_chunks:
			_dirty_chunks[chunk_id] = {}
		for idx in incoming_delta:
			_dirty_chunks[chunk_id][idx] = incoming_delta[idx]
		return
	# Host digging: wrap so the same handler works for both paths
	_server_apply_all_chunks({chunk_id: incoming_delta})

# Called by soil_gun after every shot.
# Sends all dirty chunks in ONE unreliable packet — atomic UDP delivery means
# boundary-adjacent chunks either both arrive or neither does, never one without the other.
func send_dirty() -> void:
	if multiplayer.is_server() or _dirty_chunks.is_empty():
		return
	_request_chunk_changes.rpc_id(1, _dirty_chunks)

# Called by soil_gun when the dig button is released.
func flush_pending() -> void:
	if not _dirty_chunks.is_empty():
		_flush_chunk_changes.rpc_id(1, _dirty_chunks)
	_dirty_chunks.clear()

# Unreliable: one packet per shot with all affected chunks bundled together.
# Newer packets supersede older ones so there is no queue buildup on the host.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _request_chunk_changes(all_deltas: Dictionary) -> void:
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
	_server_apply_all_chunks(all_deltas)

# Reliable: sent once on button release, guarantees final state is written to disk.
@rpc("any_peer", "call_remote", "reliable")
func _flush_chunk_changes(all_deltas: Dictionary) -> void:
	for chunk_id in all_deltas:
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			chunk_instance.delta[idx] = all_deltas[chunk_id][idx]
	_server_apply_all_chunks(all_deltas)

# Writes bins and rebuilds meshes for ALL chunks first, then broadcasts ONE combined
# update. Clients always update boundary-adjacent chunks simultaneously, keeping
# point_values in sync and preventing diverging deltas on subsequent shots.
func _server_apply_all_chunks(all_deltas: Dictionary) -> void:
	for chunk_id in all_deltas:
		_write_chunk_bin(chunk_id)
		_update_chunk_mesh(chunk_id)
		# Keep server-side point_values in sync so host digging reads correct values
		var chunk_instance = get_child(chunk_id)
		for idx in all_deltas[chunk_id]:
			if idx < chunk_instance.point_values.size():
				chunk_instance.point_values[idx] = all_deltas[chunk_id][idx]
	_receive_chunk_changes.rpc(all_deltas)

# Clients receive all chunks from one shot/flush in one RPC and apply them together.
@rpc("authority", "call_remote", "reliable")
func _receive_chunk_changes(all_deltas: Dictionary) -> void:
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
	var path = "user://player_delta/test_planet/%d.bin" % chunk_id
	var data := PackedByteArray()
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

	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.put_u8(REQ_DELETE)
		socket.put_32(chunk_id)
		socket.poll()

	if print_debug:
		print("[chunks] chunk ", chunk_id, " unloaded")
