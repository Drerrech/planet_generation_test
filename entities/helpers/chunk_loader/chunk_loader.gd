extends Node3D

# Computed chunk loader. Attach as a child of any object that should stream
# terrain around it (player, NPC, dropped item, ...). It detects which planet it
# is inside via a planet-group Area3D, then each time it crosses into a new chunk
# cell it computes which chunk ids fall inside the mesh / collision cubes and
# acquires/releases them on that planet's chunk manager (ref-counted, so multiple
# loaders can overlap safely).

@export_enum("sphere", "cube") var area_shape: String = "cube"
@export var load_mesh_side_size: float = 1.0
@export var load_collision_side_size: float = 1.0
# Only stream for the peer that controls this object (the player you drive).
@export var only_if_authority: bool = true

@onready var _detector: Area3D = $detector

var _chunks_ref = null            # current planet's chunk manager
var _acq_mesh: Dictionary = {}    # chunk_id -> true (mesh acquired by THIS loader)
var _acq_col: Dictionary = {}     # chunk_id -> true (collision acquired by THIS loader)
var _last_cell = null             # Vector3i of last chunk cell we refreshed at

func _ready() -> void:
	_detector.area_entered.connect(_on_area_entered)
	_detector.area_exited.connect(_on_area_exited)
	_setup_detector_shape()

# Size the detector to match the largest load region (the mesh region), so the
# loader binds to a planet exactly while its load region overlaps it.
func _setup_detector_shape() -> void:
	var size = maxf(load_mesh_side_size, load_collision_side_size)
	var cshape: CollisionShape3D = _detector.get_node("CollisionShape3D")
	if area_shape == "sphere":
		var s := SphereShape3D.new()
		s.radius = size * 0.5
		cshape.shape = s
	else:
		var b := BoxShape3D.new()
		b.size = Vector3(size, size, size)
		cshape.shape = b

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("planet"):
		_chunks_ref = area.get_parent().get_node("chunks")
		_last_cell = null  # force a refresh

func _on_area_exited(area: Area3D) -> void:
	if area.is_in_group("planet") and _chunks_ref == area.get_parent().get_node("chunks"):
		_release_all()
		_chunks_ref = null
		_last_cell = null

func _physics_process(_delta: float) -> void:
	if only_if_authority and not is_multiplayer_authority():
		return
	if _chunks_ref == null:
		return

	var local_pos = _chunks_ref.to_local(global_position)
	var cell = _cell_of(local_pos)
	if cell == _last_cell:
		return
	_last_cell = cell

	_refresh(local_pos)


func _cell_of(local_pos: Vector3) -> Vector3i:
	var cs: Vector3 = _chunks_ref.CHUNK_SIZE
	var n: Vector3i = _chunks_ref.NUM_CHUNKS_SIDE
	return Vector3i(
		floori(local_pos.x / cs.x + 0.5 * n.x),
		floori(local_pos.y / cs.y + 0.5 * n.y),
		floori(local_pos.z / cs.z + 0.5 * n.z)
	)

# All chunk ids whose cells lie within the load region (cube or inscribed sphere)
# of the given side length / diameter centered on local_pos.
func _chunks_in_region(local_pos: Vector3, side: float) -> Dictionary:
	var cs: Vector3 = _chunks_ref.CHUNK_SIZE
	var n: Vector3i = _chunks_ref.NUM_CHUNKS_SIDE
	var half = side * 0.5
	var x0 = maxi(0, floori((local_pos.x - half) / cs.x + 0.5 * n.x))
	var x1 = mini(n.x - 1, floori((local_pos.x + half) / cs.x + 0.5 * n.x))
	var y0 = maxi(0, floori((local_pos.y - half) / cs.y + 0.5 * n.y))
	var y1 = mini(n.y - 1, floori((local_pos.y + half) / cs.y + 0.5 * n.y))
	var z0 = maxi(0, floori((local_pos.z - half) / cs.z + 0.5 * n.z))
	var z1 = mini(n.z - 1, floori((local_pos.z + half) / cs.z + 0.5 * n.z))
	var sphere = area_shape == "sphere"
	var r_sq = half * half
	var result: Dictionary = {}
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				if sphere:
					# include the chunk if its box overlaps the sphere (not just
					# its center), so chunks whose surface is in range still load
					var cmin = (Vector3(x, y, z) - 0.5 * Vector3(n)) * cs
					var cmax = cmin + cs
					var nearest = local_pos.clamp(cmin, cmax)
					if nearest.distance_squared_to(local_pos) > r_sq:
						continue
				var id = x * n.y * n.z + y * n.z + z
				result[id] = true
	return result


func _refresh(local_pos: Vector3) -> void:
	var desired_mesh = _chunks_in_region(local_pos, load_mesh_side_size)
	var desired_col = _chunks_in_region(local_pos, load_collision_side_size)

	# acquire new meshes (always before collision, since collision needs the mesh)
	for id in desired_mesh:
		if id not in _acq_mesh:
			_chunks_ref.acquire_mesh(id)
			_acq_mesh[id] = true
	# acquire new collision
	for id in desired_col:
		if id not in _acq_col:
			_chunks_ref.acquire_collision(id)
			_acq_col[id] = true
	# release collision no longer wanted (before mesh)
	for id in _acq_col.keys():
		if id not in desired_col:
			_chunks_ref.release_collision(id)
			_acq_col.erase(id)
	# release meshes no longer wanted
	for id in _acq_mesh.keys():
		if id not in desired_mesh:
			_chunks_ref.release_mesh(id)
			_acq_mesh.erase(id)


func _release_all() -> void:
	if _chunks_ref == null:
		return
	for id in _acq_col.keys():
		_chunks_ref.release_collision(id)
	for id in _acq_mesh.keys():
		_chunks_ref.release_mesh(id)
	_acq_col.clear()
	_acq_mesh.clear()
