extends Node3D

const SHOOT_RATE = 12.0  # max calls per second

@onready var soil_gun = $soil_gun

var _time_to_next_shot: float = 0.0

func _ready() -> void:
	soil_gun.mode = 2
	soil_gun.r = 2
	soil_gun.soil_delta = 4

func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if _time_to_next_shot > 0:
		_time_to_next_shot -= delta
	
	if _time_to_next_shot <= 0:
		var accum = 1.0 / SHOOT_RATE - _time_to_next_shot
		
		if Input.is_action_pressed("m2"):
			soil_gun.shoot(accum)
			_time_to_next_shot = 1.0 / SHOOT_RATE
		elif Input.is_action_pressed("m1"):
			soil_gun.shoot(-accum)
			_time_to_next_shot = 1.0 / SHOOT_RATE
