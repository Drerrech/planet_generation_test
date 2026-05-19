extends CharacterBody3D

const SPEED = 24.0
const SPRINT_SPEED_FACTOR = 1.75
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.1

var planet_center = Vector3(0, 0, 0)
var gravity = 10.0

@onready var torso = $torso
@onready var head = $torso/head
@onready var camera = $torso/head/Camera3D

var input_dir = Vector2()
var jumping = false
var sprinting = false
var current_speed = SPEED

func _ready():
	if not is_multiplayer_authority():
		camera.current = false
		return
	camera.make_current()
	
	camera.cull_mask &= ~2          # camera ignores layer 2
	$torso/MeshInstance3D.layers = 2  # mesh is on layer 2
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if not is_multiplayer_authority(): return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		torso.rotate_y(deg_to_rad(event.relative.x * MOUSE_SENSITIVITY * -1))
		head.rotate_x(deg_to_rad(event.relative.y * MOUSE_SENSITIVITY * -1))
		head.rotation_degrees.x = clamp(head.rotation_degrees.x, -89, 89)

func update_inputs():
	if Input.is_action_just_pressed("space") and is_on_floor():
		jumping = true
	input_dir = Input.get_vector("a", "d", "w", "s")
	sprinting = Input.is_action_pressed("shift")

func _physics_process(delta):
	if not is_multiplayer_authority(): return

	var up = (global_position - planet_center).normalized()

	var new_basis = Basis()
	new_basis.y = up
	new_basis.x = up.cross(basis.z).normalized()
	new_basis.z = new_basis.x.cross(up).normalized()
	basis = new_basis.orthonormalized()

	var vertical_vel = velocity.dot(up)
	var horizontal_vel = velocity - up * vertical_vel

	if not is_on_floor():
		vertical_vel -= gravity * delta

	if jumping and is_on_floor():
		vertical_vel = JUMP_VELOCITY
		jumping = false

	update_inputs()
	current_speed = SPEED * (SPRINT_SPEED_FACTOR if sprinting else 1.0)

	var direction = (torso.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0:
		horizontal_vel = direction * current_speed
	else:
		horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, current_speed)

	velocity = horizontal_vel + up * vertical_vel
	up_direction = up
	move_and_slide()


func _on_chunk_loading_area_3d_area_entered(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.is_in_group("chunk"):
		var chunk_instance = area.get_parent()
		var chunks = chunk_instance.get_parent()
		chunks.load_chunk(chunk_instance.chunk_id)


func _on_chunk_loading_area_3d_area_exited(area: Area3D) -> void:
	if not is_multiplayer_authority(): return
	if area.is_in_group("chunk"):
		var chunk_instance = area.get_parent()
		var chunks = chunk_instance.get_parent()
		chunks.unload_chunk(chunk_instance.chunk_id)
