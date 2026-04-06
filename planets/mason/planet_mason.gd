@tool

extends Node3D

@export var noise_generator: FastNoiseLite:
	set(new_noise):
		noise_generator = new_noise

@onready var chunks := $chunks
const chunk_scene := preload("res://terrain/chunk/chunk.tscn")
const planet_shader = preload("res://terrain/chunk/shaders/planet_triplanar.gdshader")

var num_chunks = Vector3i(4, 4, 4)
var terrain_val_f: Callable = func(point_pos) -> float: # [0, 1]
	const planet_r = 30
	const planet_r_2 = planet_r**2
	
	var val = 0
	
	# base
	var r_2 = point_pos[0]**2 + point_pos[1]**2 + point_pos[2]**2
	val += r_2 / planet_r_2
	
	# mountains
	var noise_val = (noise_generator.get_noise_3d(point_pos[0], point_pos[1], point_pos[2]) - 1)*0.5
	noise_val = -pow(-noise_val * 1.0, 4)
	val += 0.5 * noise_val 
	
	return min(1, val)

func create_chunk(instance_name, relative_pos, num_cells, cell_size, point_max_val, f_callable):
	var chunk_instance := chunk_scene.instantiate()
	
	chunk_instance.name = instance_name
	
	chunk_instance.position = relative_pos
	chunk_instance.num_cells = num_cells
	chunk_instance.cell_size = cell_size
	chunk_instance.point_max_val = point_max_val
	chunk_instance.ISO_LEVEL = (point_max_val+1)/2
	chunk_instance.f_callable = f_callable
	
	chunks.add_child(chunk_instance) # generates the mesh
	# apply shaders
	var mat := ShaderMaterial.new()
	mat.shader = planet_shader
	mat.set_shader_parameter("texture_y_pos", preload("res://planets/mason/textures/grass.png"))
	mat.set_shader_parameter("texture_side", preload("res://planets/mason/textures/brick_wall.png"))
	mat.set_shader_parameter("texture_y_neg", preload("res://planets/mason/textures/cave_ceiling.png"))
	mat.set_shader_parameter("chunk_relative_pos", relative_pos)
	mat.set_shader_parameter("planet_gloval_pos", global_position)
	chunks.get_node(instance_name).mesh_instance.material_override = mat

func delete_chunk(instance_name):
	chunks.get_node(instance_name).queue_free()

func delete_all_chunks():
	for chunk in chunks.get_children():
		chunk.queue_free()

func create_all_chunks():
	for x in range(num_chunks[0]):
		for y in range(num_chunks[1]):
			for z in range(num_chunks[2]):
				var _instance_name = str(x)+"_"+str(y)+"_"+str(z)
				
				var _num_cells = Vector3i(64, 64, 64)
				var _cell_size = Vector3(1, 1, 1)
				
				var _relative_pos = (Vector3(x, y, z) - num_chunks/2.0) * Vector3(_num_cells)*_cell_size
				
				var _point_max_val = 15
				
				create_chunk(_instance_name, _relative_pos, _num_cells, _cell_size, _point_max_val, terrain_val_f)


func generate_planet():
	delete_all_chunks()
	create_all_chunks()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var time = Time.get_ticks_msec()
	generate_planet()
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	print("Terrain generated in: " + str(elapsed) + "s")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
