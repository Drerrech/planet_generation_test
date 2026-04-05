@tool

extends Node3D

var num_cells := Vector3i(10, 10, 10)
var cell_size := Vector3(1, 1, 1)
var point_max_val := 1
@warning_ignore("unused_parameter")
var f_callable: Callable = func(pos) -> float:
	return randf()
@warning_ignore("integer_division")
var ISO_LEVEL = (point_max_val+1)/2 # not inclusive

class VoxelGrid:
	var point_values: PackedByteArray # NOTE: each side is (size+1), 1D array
	var num_cells: Vector3i
	var point_max_val: int
	
	func _init(_num_cells: Vector3i, _point_max_val: int):
		self.num_cells = _num_cells
		self.point_max_val = _point_max_val
		self.point_values.resize((num_cells[0]+1) * (num_cells[1]+1) * (num_cells[2]+1))
	
	func get_idx(x: int, y: int, z: int):
		return (num_cells[1]+1)*(num_cells[2]+1)*x + (num_cells[2]+1)*y + z
	
	func elem_set(x: int, y: int, z: int, elem: int):
		point_values[get_idx(x, y, z)] = elem
	func elem_get(x: int, y: int, z: int):
		return point_values[get_idx(x, y, z)]

var vertices:PackedVector3Array
var grid = null

@onready var mesh_instance := $chunk_mesh
const tables := preload("res://terrain/chunk/marching_cubes_resources.gd")


func fill_grid():
	for x in range(num_cells[0] + 1):
		for y in range(num_cells[1] + 1):
			for z in range(num_cells[2] + 1):
				var relative_pos = position + Vector3(x, y, z) * cell_size
				grid.elem_set(x, y, z, floori(f_callable.call(relative_pos) * (point_max_val+1 - 1e-6)))

func get_triangulation(x:int, y:int, z:int):
	var idx = 0b00000000
	idx |= int(grid.elem_get(x, y, z) < ISO_LEVEL)<<0
	idx |= int(grid.elem_get(x, y, z+1) < ISO_LEVEL)<<1
	idx |= int(grid.elem_get(x+1, y, z+1) < ISO_LEVEL)<<2
	idx |= int(grid.elem_get(x+1, y, z) < ISO_LEVEL)<<3
	idx |= int(grid.elem_get(x, y+1, z) < ISO_LEVEL)<<4
	idx |= int(grid.elem_get(x, y+1, z+1) < ISO_LEVEL)<<5
	idx |= int(grid.elem_get(x+1, y+1, z+1) < ISO_LEVEL)<<6
	idx |= int(grid.elem_get(x+1, y+1, z) < ISO_LEVEL)<<7
	return tables.TRIANGULATIONS[idx]

func calculate_interpolation(a:Vector3, b:Vector3):
	var val_a = grid.elem_get(int(a.x), int(a.y), int(a.z))
	var val_b = grid.elem_get(int(b.x), int(b.y), int(b.z))
	var t = (ISO_LEVEL-0.5 - val_a)/(val_b-val_a)
	return a+t*(b-a)

func march_cube(x:int, y:int, z:int):
  # Get the correct configuration
	var tri = get_triangulation(x, y, z)
	for edge_index in tri:
		if edge_index < 0: break
		# Get edge
		var point_indices = tables.EDGES[edge_index]
		# Get 2 points connecting this edge
		var p0 = tables.POINTS[point_indices.x]
		var p1 = tables.POINTS[point_indices.y]
		# Global position of these 2 points
		var pos_a = Vector3(x+p0.x, y+p0.y, z+p0.z)
		var pos_b = Vector3(x+p1.x, y+p1.y, z+p1.z)
		# Interpolate between these 2 points to get our mesh's vertex position
		var pos = calculate_interpolation(pos_a, pos_b) * cell_size
		# Add our new vertex to our mesh's vertces array
		vertices.append(pos)

func march_cube_across_grid(): # adds verticies to verticices array
	for x in range(num_cells[0]):
		for y in range(num_cells[1]):
			for z in range(num_cells[2]):
				march_cube(x, y, z)

func build_mesh():
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vert in vertices:
		surface_tool.add_vertex(vert)
	
	surface_tool.generate_normals()
	surface_tool.index()
	mesh_instance.mesh = surface_tool.commit()

func display_point_vals(): # debug
	for x in range(num_cells[0]+1):
		for y in range(num_cells[1]+1):
			for z in range(num_cells[2]+1):
				var _mesh_instance := MeshInstance3D.new()
				var text_mesh := TextMesh.new()
				text_mesh.text = str(grid.elem_get(x, y, z))
				text_mesh.font_size = 32
				text_mesh.depth = 0.1
				_mesh_instance.mesh = text_mesh
				_mesh_instance.position = Vector3(x, y, z) * cell_size
				add_child(_mesh_instance)

# Called when the node enters the scene tree for the first time.
func generate() -> void:
	grid = VoxelGrid.new(num_cells, point_max_val)
	
	fill_grid()
	march_cube_across_grid()
	build_mesh()
	#display_point_vals()

func _ready() -> void:
	generate()
