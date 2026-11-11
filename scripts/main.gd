extends Node3D
## Sandbox entry point: the house, one local player with every weapon, and
## respawning dummy targets. Rounds and networking replace this later.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DUMMY_RESPAWN_TIME := 3.0
const DUMMY_COLOR := Color(0.8, 0.3, 0.25)

## Position and facing (yaw in degrees) of each dummy target.
const DUMMIES := [
	[Vector3(3, 0, 7), 180.0],
	[Vector3(0, 0, 0.5), 180.0],
	[Vector3(-5.5, 0, 3.5), -90.0],
	[Vector3(5.5, 0, -3.5), 135.0],
	[Vector3(0, 3, 0), 180.0],
	[Vector3(-5, 3, -3), -135.0],
]

var _player: Player

@onready var _hud: Hud = $Hud


func _ready() -> void:
	add_child(House.new())
	_player = _spawn(Vector3(0, 0.1, 9), 0.0, true)
	_player.arsenal.equip(["carbine", "pistol", "shotgun"])
	_player.died.connect(_respawn_later.bind(_player.global_transform))
	_hud.player = _player
	for spec: Array in DUMMIES:
		var dummy := _spawn(spec[0], spec[1], false)
		dummy.body.set_color(DUMMY_COLOR)
		dummy.arsenal.equip(["pistol"])
		dummy.died.connect(_respawn_later.bind(dummy.global_transform))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn(at: Vector3, yaw_deg: float, local: bool) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = local
	player.position = at
	player.rotation_degrees.y = yaw_deg
	add_child(player)
	return player


func _respawn_later(victim: Player, _killer: Node, at: Transform3D) -> void:
	await get_tree().create_timer(DUMMY_RESPAWN_TIME).timeout
	victim.respawn(at)
