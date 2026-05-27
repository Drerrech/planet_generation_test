@tool

extends MeshInstance3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	var arrays = sphere.surface_get_arrays(0)
	var verts = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]

	var new_verts = PackedVector3Array()
	for idx in indices:
		new_verts.append(verts[idx])

	var new_arrays = []
	new_arrays.resize(Mesh.ARRAY_MAX)
	new_arrays[Mesh.ARRAY_VERTEX] = new_verts

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	
	self.mesh = mesh


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
