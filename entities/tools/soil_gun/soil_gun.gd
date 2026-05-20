extends Node3D

@onready var indicators = $indicators
@onready var raycast: RayCast3D = $RayCast3D

# 1 - uniform sphere
# 2 - smooth sphere
var mode = 2
var r = 2
var soil_delta = 1.0

var _last_chunks_ref = null

var _indicator_mesh: SphereMesh
var _indicator_mat: StandardMaterial3D

func _ready() -> void:
	# indicators live in world space so they don't move with the player
	indicators.top_level = true

	_indicator_mesh = SphereMesh.new()
	_indicator_mesh.radius = 0.1
	_indicator_mesh.height = 0.2

	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.albedo_color = Color(1, 0, 0, 0.8)
	_indicator_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _clear_indicators() -> void:
	for child in indicators.get_children():
		child.queue_free()

func _show_indicators(chunks_ref: Node, affected: Dictionary) -> void:
	var CHUNK_SIDE_SIZE: int = chunks_ref.CHUNK_SIDE_SIZE
	var cell_size: float = chunks_ref.CHUNK_SIZE.x / (CHUNK_SIDE_SIZE - 1)

	for chunk_id in affected:
		var chunk_instance = chunks_ref.get_child(chunk_id)
		var chunk_world_pos = chunk_instance.global_position

		for local_idx in affected[chunk_id]:
			var lx = local_idx / (CHUNK_SIDE_SIZE * CHUNK_SIDE_SIZE)
			var ly = (local_idx / CHUNK_SIDE_SIZE) % CHUNK_SIDE_SIZE
			var lz = local_idx % CHUNK_SIDE_SIZE
			var voxel_world = chunk_world_pos + Vector3(lx, ly, lz) * cell_size

			var indicator = MeshInstance3D.new()
			indicator.mesh = _indicator_mesh
			indicator.material_override = _indicator_mat
			indicators.add_child(indicator)
			indicator.global_position = voxel_world

func _process(_delta: float) -> void:
	_clear_indicators()

	if not is_multiplayer_authority() or not raycast.is_colliding():
		return
	if not raycast.get_collider().is_in_group("chunk"):
		return
	
	var chunks_ref = raycast.get_collider().get_parent()
	var collision_point = raycast.get_collision_point()

	match mode:
		1:  # uniform sphere
			var affected = ChunkModification._get_affected_voxels(chunks_ref, collision_point, r)
			_show_indicators(chunks_ref, affected)
		2:  # smooth sphere
			var affected = ChunkModification._get_affected_voxels(chunks_ref, collision_point, r)
			_show_indicators(chunks_ref, affected)

func shoot(time_delta: float) -> void:
	if not raycast.is_colliding():
		return
	if not raycast.get_collider().is_in_group("chunk"):
		return

	var chunks_ref = raycast.get_collider().get_parent()
	_last_chunks_ref = chunks_ref
	var collision_point = raycast.get_collision_point()

	match mode:
		1:  # uniform sphere
			ChunkModification.spherical_uniform_add_delta(chunks_ref, collision_point, r, soil_delta * time_delta)
		2:  # smooth sphere
			ChunkModification.spherical_smooth_add_delta(chunks_ref, collision_point, r, soil_delta * time_delta)

	chunks_ref.send_dirty()

func flush() -> void:
	if _last_chunks_ref != null:
		_last_chunks_ref.flush_pending()
		_last_chunks_ref = null
		
