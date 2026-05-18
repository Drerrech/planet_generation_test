@tool

extends Node3D

@onready var chunks = $chunks

func _ready() -> void:
	var time = Time.get_ticks_msec()
	
	await chunks.init()

	# init all chunks
	chunks.add_all_chunks()

	# generate all chunks, yielding once per frame to keep editor responsive
	var frame_start = Time.get_ticks_msec()
	for i in range(chunks.NUM_CHUNKS):
		chunks.load_chunk(i)
		if Time.get_ticks_msec() - frame_start >= 128:
			await get_tree().process_frame
			frame_start = Time.get_ticks_msec()
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	print("Terrain generated in: " + str(elapsed) + "s")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
