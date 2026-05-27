extends Node3D

@onready var particles = $GPUParticles3D
@onready var player = get_parent().get_parent()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	particles.emitting = player.space_pressed and player.flying_on
