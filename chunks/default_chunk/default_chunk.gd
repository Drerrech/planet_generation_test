#@tool

extends Node3D

var chunk_id: int = -1
@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D

var loaded = false
var delta = {}

@onready var path = "user://player_delta/test_planet/%d.bin" % chunk_id

func load_chunk():
	return
	if chunk_id == -1:
		print("ERROR: unassigned chunk being loaded")
		return
	
	# update status
	loaded = true
	
	# read delta
	delta = {}
	if not FileAccess.file_exists(path):
		return
	var f = FileAccess.open(path, FileAccess.READ)
	while f.get_position() < f.get_length():
		var idx = f.get_32()
		var val = f.get_float()
		delta[idx] = val
	f.close()

func unload_chunk():
	return
	if chunk_id == -1:
		print("ERROR: unassigned chunk being loaded")
		return
	
	# update status
	loaded = false
	
	# read delta
	var f = FileAccess.open(path, FileAccess.WRITE)  # WRITE truncates existing file
	for idx in delta:
		f.store_32(idx)
		f.store_float(delta[idx])
	f.close()

func apply_changes(incoming_delta:Dictionary):
	if loaded:
		for idx in incoming_delta:
			delta[idx] = incoming_delta[idx]
	else:
		load_chunk()
		for idx in incoming_delta:
			delta[idx] = incoming_delta[idx]
		unload_chunk()
