#@tool

extends Node3D

var chunk_id: int = -1
@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D

var loaded = false
var delta = {}
var point_values: PackedFloat32Array = PackedFloat32Array()

func load_chunk():
	loaded = true

func unload_chunk():
	loaded = false

func apply_changes(incoming_delta: Dictionary):
	for idx in incoming_delta:
		delta[idx] = incoming_delta[idx]
		if idx < point_values.size():
			point_values[idx] = incoming_delta[idx]
	get_parent().on_chunk_changed(chunk_id, incoming_delta)
