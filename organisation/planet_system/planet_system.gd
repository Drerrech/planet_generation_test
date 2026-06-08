extends Node

const PORT = 8998
const player_scene = preload("res://entities/player/player.tscn")

@onready var _spawner: MultiplayerSpawner = $players/MultiplayerSpawner
@onready var _players: Node = $players

func _ready() -> void:
	_spawner.spawn_function = _spawn_function
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if GameState.is_server:
		start_server()
	else:
		start_client()

func start_server() -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	_spawn_player(multiplayer.get_unique_id())

func start_client() -> void:
	var peer = ENetMultiplayerPeer.new()
	peer.create_client(GameState.server_ip, PORT)
	multiplayer.multiplayer_peer = peer
	# client's own player is spawned by the server via MultiplayerSpawner

func _spawn_function(id: int) -> Node:
	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = Vector3(0, 410, 0)
	player.set_multiplayer_authority(id)
	return player

func _spawn_player(id: int) -> void:
	if not multiplayer.is_server(): return
	_spawner.spawn(id)

func _on_peer_connected(id: int) -> void:
	_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server(): return
	var player = _players.get_node_or_null(str(id))
	if player:
		player.queue_free()
