extends Node2D

@onready var fps_counter = $fps_counter

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _process(delta):
	fps_counter.text = str(Engine.get_frames_per_second()) + " fps"
