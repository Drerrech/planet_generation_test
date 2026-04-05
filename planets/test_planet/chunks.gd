@tool

extends Node

const chunk_scene := preload("res://chunks/default_chunk/default_chunk.tscn")

# NOTE: MUST BE THE SAME AS EXECUTABLE
const NUM_CHUNKS_SIDE = Vector3i(4, 4, 4)
const NUM_CHUNKS = NUM_CHUNKS_SIDE.x * NUM_CHUNKS_SIDE.y * NUM_CHUNKS_SIDE.z
const CHUNK_SIZE = Vector3(64.0, 64.0, 64.0)

const REQ_GENERATE = 1
const REQ_DELETE   = 2
const VERTEX_SIZE  = 3 * 4  # 3 floats * 4 bytes

var socket := StreamPeerTCP.new()
var pid: int = -1

func init() -> void:
	print("[chunks] spawning server process...")
	var exe_path = ProjectSettings.globalize_path("res://chunk_executables/test_server")
	pid = OS.create_process(exe_path, [])

	await get_tree().create_timer(0.2).timeout

	print("[chunks] connecting to server...")
	var err = socket.connect_to_host("127.0.0.1", 9000)
	if err != OK:
		print("[chunks] connect_to_host failed: ", err)
		return

	while true:
		socket.poll()
		var status = socket.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			break
		if status == StreamPeerTCP.STATUS_ERROR:
			print("[chunks] socket connection failed")
			return
		await get_tree().process_frame

	print("[chunks] connected to server")

func _exit_tree():
	print("[chunks] disconnecting and killing server process...")
	socket.disconnect_from_host()
	if pid != -1:
		OS.kill(pid)
		pid = -1
	print("[chunks] server killed")

func request_generate(chunk_id: int, x: float, y: float, z: float) -> PackedVector3Array:
	print("[chunks] requesting generation for chunk ", chunk_id, " at (", x, ", ", y, ", ", z, ")")
	
	socket.put_u8(REQ_GENERATE)
	socket.put_32(chunk_id)
	socket.put_float(x)
	socket.put_float(y)
	socket.put_float(z)
	socket.poll()  # flush the send buffer

	var timeout = 0
	while true:
		socket.poll()
		if socket.get_available_bytes() >= 4:
			break
		await get_tree().process_frame
		timeout += 1
		if timeout > 300:
			print("[chunks] ERROR: timed out waiting for vertex count")
			return PackedVector3Array()
	
	var vertex_count = socket.get_32()
	print("[chunks] chunk ", chunk_id, " expecting ", vertex_count, " vertices")

	var total_bytes = vertex_count * VERTEX_SIZE
	
	while true:
		socket.poll()
		var available = socket.get_available_bytes()
		print(available)
		if available >= total_bytes:
			break
		await get_tree().process_frame

	var result = socket.get_data(total_bytes)
	if result[0] != OK:
		print("[chunks] ERROR: get_data failed: ", result[0])
		return PackedVector3Array()

	var bytes: PackedByteArray = result[1]

	var verts = PackedVector3Array()
	verts.resize(vertex_count)
	for i in range(vertex_count):
		var offset = i * VERTEX_SIZE
		verts[i] = Vector3(
			bytes.decode_float(offset),
			bytes.decode_float(offset + 4),
			bytes.decode_float(offset + 8)
		)

	print("[chunks] chunk ", chunk_id, " received ", verts.size(), " vertices")
	return verts

func build_mesh(verts: PackedVector3Array) -> ArrayMesh:
	print("[chunks] building mesh with ", verts.size(), " vertices")
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		st.add_vertex(v)
	st.index()
	st.generate_normals()
	var mesh = st.commit()
	print("[chunks] mesh built")
	return mesh

func add_all_chunks() -> void:
	print("[chunks] adding ", NUM_CHUNKS, " chunks...")
	var id = 0
	for x in range(NUM_CHUNKS_SIDE.x):
		for y in range(NUM_CHUNKS_SIDE.y):
			for z in range(NUM_CHUNKS_SIDE.z):
				var chunk_instance = chunk_scene.instantiate()
				chunk_instance.chunk_id = id
				chunk_instance.position = Vector3(x, y, z) * CHUNK_SIZE
				add_child(chunk_instance)
				unload_chunk(id)
				id += 1
	print("[chunks] all chunks added")

func load_chunk(chunk_id: int) -> void:
	print("Children count:", get_child_count())
	print("[chunks] loading chunk ", chunk_id, "...")
	var chunk_instance = get_child(chunk_id)
	print("Node:", chunk_instance)
	
	var raw_vertices: PackedVector3Array = await request_generate(chunk_id, chunk_instance.position.x, chunk_instance.position.y, chunk_instance.position.z)
	chunk_instance.mesh_instance.mesh = build_mesh(raw_vertices)
	print("[chunks] chunk ", chunk_id, " loaded")

func unload_chunk(chunk_id: int) -> void:
	print("[chunks] unloading chunk ", chunk_id, " (TODO)")
	pass
