extends Node3D
## Entry point: the house and one local player. Rounds and networking come later.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: Player

@onready var _readout: Label = $Hud/Readout
@onready var _prompt: Label = $Hud/Prompt


func _ready() -> void:
	add_child(House.new())
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector3(0, 0.1, 9)
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
	_readout.text = "speed %.1f m/s   %s   lean %+.2f\nWASD move | Shift sprint | Ctrl/C crouch | Q/E lean | F door | V crack door | Esc free mouse" \
			% [speed, stance, _player.lean_frac]

	var door := _player.aimed_door()
	_prompt.visible = door != null
	if door != null:
		_prompt.text = "%s (%s)\n[F] %s    [V] %s" % [
			door.door_name, Door.State.keys()[door.state].to_lower(),
			"close" if door.state == Door.State.OPEN else "open",
			"close" if door.state == Door.State.CRACKED else "crack"]
