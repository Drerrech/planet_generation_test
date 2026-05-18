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
const VERTEX_SIZE  = 3 * 4  # 3 floats * 4 bytes

var socket := StreamPeerTCP.new()
var pid: int = -1

# NOTE: port is hardcoded per role — 8999 for host, 9000 for client.
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

	# unload all chunks (write delta to memory)
	for i in range(NUM_CHUNKS):
		var chunk_instance = get_child(i)
		chunk_instance.unload_chunk()

func request_generate(chunk_id: int, x: float, y: float, z: float) -> PackedVector3Array:
	if print_debug:
		print("[chunks] requesting generation for chunk ", chunk_id, " at (", x, ", ", y, ", ", z, ")")

	socket.put_u8(REQ_GENERATE)
	socket.put_32(chunk_id)
	socket.put_float(x)
	socket.put_float(y)
	socket.put_float(z)
	socket.poll()  # flush send buffer

	# spin until vertex count arrives — on localhost this is microseconds
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
	if print_debug:
		print("[chunks] chunk ", chunk_id, " expecting ", vertex_count, " vertices")

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
			deadline = Time.get_ticks_msec() + 10000  # reset timeout while data flows

	var verts := PackedVector3Array()
	verts.resize(vertex_count)
	for i in range(vertex_count):
		var offset = i * VERTEX_SIZE
		verts[i] = Vector3(
			bytes.decode_float(offset),
			bytes.decode_float(offset + 4),
			bytes.decode_float(offset + 8)
		)

	if print_debug:
		print("[chunks] chunk ", chunk_id, " received ", verts.size(), " vertices")
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
		# TODO DIGGING: if player already has local bin data (visited before), could generate immediately
		request_bin_data.rpc_id(1, chunk_id)
		return

	_generate_and_apply_mesh(chunk_id)


func _generate_and_apply_mesh(chunk_id: int) -> void:
	var chunk_instance = get_child(chunk_id)

	var raw_vertices: PackedVector3Array = request_generate(
		chunk_id,
		chunk_instance.position.x,
		chunk_instance.position.y,
		chunk_instance.position.z
	)
	if print_debug:
		print("[chunks] _generate_and_apply_mesh chunk ", chunk_id, " got ", raw_vertices.size(), " vertices")

	var mesh = build_mesh(raw_vertices)
	chunk_instance.mesh_instance.mesh = mesh

	var test_shader = ShaderMaterial.new()
	test_shader.shader = preload("res://planets/test_planet/shaders/test_shader.gdshader")
	chunk_instance.mesh_instance.material_override = test_shader

	if mesh.get_surface_count() > 0:
		chunk_instance.collision_shape.shape = mesh.create_trimesh_shape()

	if print_debug:
		print("[chunks] chunk ", chunk_id, " loaded")


@rpc("any_peer", "call_remote", "reliable")
func request_bin_data(chunk_id: int) -> void:
	if print_debug:
		print("[chunks] request_bin_data received for chunk ", chunk_id, " from peer ", multiplayer.get_remote_sender_id())
	# TODO DIGGING: when digging is added, server will also push updated bin data to nearby clients
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
	# TODO DIGGING: receiving updated bin data mid-game (after a dig) will need to re-generate the mesh
	if data.size() > 0:
		var dir = "user://player_delta/test_planet"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f = FileAccess.open("%s/%d.bin" % [dir, chunk_id], FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
	_generate_and_apply_mesh(chunk_id)


func unload_chunk(chunk_id: int) -> void:
	if print_debug:
		print("[chunks] unloading chunk ", chunk_id, " (TODO)")

	var chunk_instance = get_child(chunk_id)
	chunk_instance.unload_chunk()

	if print_debug:
		print("Node:", chunk_instance)

	# TODO: instead of full mesh return simplified version, for now empty
	chunk_instance.mesh_instance.mesh = null
	chunk_instance.collision_shape.shape = null

	if print_debug:
		print("[chunks] chunk ", chunk_id, " unloaded")
