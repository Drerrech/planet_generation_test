extends Control

@onready var ip_input: LineEdit = $VBoxContainer/IPInput

func _on_host_pressed() -> void:
	GameState.is_server = true
	get_tree().change_scene_to_file("res://organisation/planet_system/planet_system.tscn")

func _on_join_pressed() -> void:
	GameState.is_server = false
	GameState.server_ip = ip_input.text.strip_edges()
	get_tree().change_scene_to_file("res://organisation/planet_system/planet_system.tscn")
