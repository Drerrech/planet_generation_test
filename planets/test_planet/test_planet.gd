@tool

extends Node3D

@onready var chunks = $chunks

func _ready() -> void:
	var time = Time.get_ticks_msec()
	
	await chunks.init()
	
	# init all chunks
	await chunks.add_all_chunks()
	
	# generate all chunks
	for i in range(chunks.NUM_CHUNKS):
		await chunks.load_chunk(i)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	print("Terrain generated in: " + str(elapsed) + "s")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
