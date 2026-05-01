extends CharacterBody3D

const SPEED = 12.0
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
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
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
	var up = (global_position - planet_center).normalized()

	# align player basis to planet surface using player's own forward — stable, no feedback loop
	var new_basis = Basis()
	new_basis.y = up
	new_basis.x = basis.z.cross(up).normalized()
	new_basis.z = up.cross(new_basis.x).normalized()
	basis = new_basis.orthonormalized()

	# decompose velocity into surface-normal and tangent components
	var vertical_vel = velocity.dot(up)
	var horizontal_vel = velocity - up * vertical_vel

	# gravity
	if not is_on_floor():
		vertical_vel -= gravity * delta

	# jump
	if jumping and is_on_floor():
		vertical_vel = JUMP_VELOCITY
		jumping = false

	update_inputs()
	current_speed = SPEED * (SPRINT_SPEED_FACTOR if sprinting else 1.0)

	# movement relative to torso direction in world space
	var direction = (torso.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction.length() > 0:
		horizontal_vel = direction * current_speed
	else:
		horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, current_speed)

	velocity = horizontal_vel + up * vertical_vel

	up_direction = up
	move_and_slide()


func _on_chunk_loading_area_3d_area_entered(area: Area3D) -> void:
	if area.is_in_group("chunk"):
		# load this chunk through its parent (chunks)
		var chunk_instance = area.get_parent()
		var chunks = chunk_instance.get_parent()
		
		chunks.load_chunk(chunk_instance.chunk_id)


func _on_chunk_loading_area_3d_area_exited(area: Area3D) -> void:
	if area.is_in_group("chunk"):
		# unload this chunk through its parent (chunks)
		var chunk_instance = area.get_parent()
		var chunks = chunk_instance.get_parent()
		
		chunks.unload_chunk(chunk_instance.chunk_id)
