extends Node3D

const SHOOT_RATE = 24.0  # max calls per second

@onready var soil_gun = $soil_gun

var _time_to_next_shot: float = 0.0
var _was_digging: bool = false

func _ready() -> void:
	soil_gun.mode = 2
	soil_gun.r = 2
	soil_gun.soil_delta = 2

func update_inputs():
	if Input.is_action_pressed("1"):
		soil_gun.r = 1
	if Input.is_action_pressed("2"):
		soil_gun.r = 2
	if Input.is_action_pressed("3"):
		soil_gun.r = 3
	

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	
	update_inputs()

	var digging = Input.is_action_pressed("m1") or Input.is_action_pressed("m2")

	if _was_digging and not digging:
		soil_gun.flush()

	_was_digging = digging

	if _time_to_next_shot > 0:
		_time_to_next_shot -= delta

	if _time_to_next_shot <= 0 and digging:
		var accum = 1.0 / SHOOT_RATE - _time_to_next_shot

		if Input.is_action_pressed("m2"):
			soil_gun.shoot(accum)
			_time_to_next_shot = 1.0 / SHOOT_RATE
		elif Input.is_action_pressed("m1"):
			soil_gun.shoot(-accum)
			_time_to_next_shot = 1.0 / SHOOT_RATE
