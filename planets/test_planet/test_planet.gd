#@tool

extends Node3D

@onready var chunks = $chunks

func _ready() -> void:
	var time = Time.get_ticks_msec()
	
	await chunks.init()
	# Chunks are no longer pre-instantiated. ChunkLoader nodes (on the player and
	# other objects) stream chunks in/out around themselves on demand.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
