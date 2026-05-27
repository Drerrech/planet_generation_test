extends CharacterBody3D

const SPEED = 6.0
const SPRINT_SPEED_FACTOR = 1.5
const JUMP_VELOCITY = 4.5
const FLY_VERTICAL_ACC = 20.0
const FLY_SPRINT_SPEED_FACTOR = 3.0
const MOUSE_SENSITIVITY = 0.1

var planet_center = Vector3(0, 0, 0)
var gravity = 10.0

@onready var torso = $torso
@onready var head = $torso/head
@onready var camera = $torso/head/Camera3D
@onready var floor_col = $ShapeCast3D

var input_dir = Vector2()
var space_just_pressed = false
var space_pressed = false
var sprinting = false
var current_speed = SPEED

var jumping = false
var flying_on = false

func _ready():
	if not is_multiplayer_authority():
		camera.current = false
		return
	camera.make_current()
	
	camera.cull_mask &= ~2          # camera ignores layer 2
	$torso/MeshInstance3D.layers = 2  # mesh is on layer 2
	$torso/jetpack/MeshInstance3D.layers = 2  # mesh is on layer 2
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if not is_multiplayer_authority(): return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		torso.rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY * -1))
		head.rotate_x(deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		head.rotation_degrees.x = clamp(head.rotation_degrees.x, -89, 89)

func update_inputs():
	space_just_pressed = Input.is_action_just_pressed("space")
	space_pressed = Input.is_action_pressed("space")
	
	input_dir = Input.get_vector("a", "d", "w", "s")
	sprinting = Input.is_action_pressed("shift")

func _physics_process(delta):
	update_inputs()
	
	if not is_multiplayer_authority(): return

	var up = (global_position - planet_center).normalized()

	var new_basis = Basis()
	new_basis.y = up
	new_basis.x = up.cross(basis.z).normalized()
	new_basis.z = new_basis.x.cross(up).normalized()
	basis = new_basis.orthonormalized()

	var vertical_vel = velocity.dot(up)
	var horizontal_vel = velocity - up * vertical_vel

	if not floor_col.is_colliding():
		vertical_vel -= gravity * delta
		if space_just_pressed:
			flying_on = true
	else:
		flying_on = false
		if space_pressed:
			vertical_vel = JUMP_VELOCITY
	
	if flying_on and space_pressed:
		vertical_vel += delta * FLY_VERTICAL_ACC

	if not flying_on:
		current_speed = SPEED * (SPRINT_SPEED_FACTOR if sprinting else 1.0)
	else:
		current_speed = SPEED * (FLY_SPRINT_SPEED_FACTOR if sprinting else 1.0)

	var direction = (torso.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0:
		horizontal_vel = direction * current_speed
	else:
		horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, current_speed)

	velocity = horizontal_vel + up * vertical_vel
	up_direction = up
	move_and_slide()


func _process(_delta):
	pass


func _on_chunk_mesh_area_area_entered(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.is_in_group("chunk"):
		var chunk_instance = area.get_parent()
		chunk_instance.get_parent().load_chunk(chunk_instance.chunk_id, false)


func _on_chunk_mesh_area_area_exited(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.is_in_group("chunk"):
		var chunk_instance = area.get_parent()
		chunk_instance.get_parent().unload_chunk(chunk_instance.chunk_id)


func _on_chunk_collision_area_area_entered(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.is_in_group("chunk"):
		var chunk_instance = area.get_parent()
		chunk_instance.get_parent().load_chunk(chunk_instance.chunk_id, true)


func _on_chunk_collision_area_area_exited(area: Area3D) -> void:
	pass
