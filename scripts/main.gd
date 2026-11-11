extends Node3D
## Milestone 1 entry point: a movement test room with one local player.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const FLOOR := Color(0.45, 0.45, 0.45)
const WALL := Color(0.75, 0.72, 0.65)
const ACCENT := Color(0.85, 0.5, 0.2)

var _player: Player

@onready var _readout: Label = $Hud/Readout


func _ready() -> void:
	_build_test_room()
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector3(0, 0.1, 6)
	add_child(_player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var stance := "CROUCH" if _player.is_crouching() else ("SPRINT" if _player.is_sprinting() else "STAND")
	_readout.text = "speed %.1f m/s   %s   lean %+.2f\nWASD move | Shift sprint | Ctrl/C crouch | Q/E lean | Esc free mouse" \
			% [speed, stance, _player.lean_frac]


func _build_test_room() -> void:
	Greybox.add_box(self, Vector3(0, -0.25, 0), Vector3(24, 0.5, 24), FLOOR)
	# Perimeter.
	Greybox.add_box(self, Vector3(0, 1.5, -12), Vector3(24, 3, 0.3), WALL)
	Greybox.add_box(self, Vector3(0, 1.5, 12), Vector3(24, 3, 0.3), WALL)
	Greybox.add_box(self, Vector3(-12, 1.5, 0), Vector3(0.3, 3, 24), WALL)
	Greybox.add_box(self, Vector3(12, 1.5, 0), Vector3(0.3, 3, 24), WALL)
	# Dividing wall with a 1 m doorway: stand beside it and lean to slice the far side.
	Greybox.add_box(self, Vector3(-6.25, 1.5, 0), Vector3(11.5, 3, 0.3), WALL)
	Greybox.add_box(self, Vector3(6.25, 1.5, 0), Vector3(11.5, 3, 0.3), WALL)
	Greybox.add_box(self, Vector3(0, 2.6, 0), Vector3(1.0, 0.8, 0.3), WALL)
	# Targets to look for from the doorway.
	Greybox.add_box(self, Vector3(-4, 0.9, -6), Vector3(0.6, 1.8, 0.6), ACCENT)
	Greybox.add_box(self, Vector3(5, 0.9, -8), Vector3(0.6, 1.8, 0.6), ACCENT)
	# Low beam: only passable crouched, and you cannot stand up under it.
	Greybox.add_box(self, Vector3(-7, 2.15, 6), Vector3(4, 1.7, 3), ACCENT)
	# Ramp at stair angle.
	Greybox.add_box(self, Vector3(8, 1.15, 6), Vector3(2, 0.2, 5), ACCENT, Vector3(30, 0, 0))
