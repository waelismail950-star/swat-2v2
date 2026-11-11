extends Node3D
## Local test mode: one human and three bots play a full match in the house.
## The human's roster plays Entry first.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var game: Match
var _local: Player

@onready var _hud: Hud = $Hud


func _ready() -> void:
	var house := House.new()
	add_child(house)
	var hostage := Hostage.new()
	add_child(hostage)
	game = Match.new(house, hostage)
	add_child(game)

	_local = _add_player("You", 0, false)
	_add_player("Bot Alpha", 0, true)
	_add_player("Bot Bravo", 1, true)
	_add_player("Bot Charlie", 1, true)
	_hud.player = _local
	_hud.game = game
	game.start_match()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# A downed player watches through their teammate's eyes.
	var view := _local
	if _local.is_dead:
		for mate in game.players_on(_local.team):
			if not mate.is_dead:
				view = mate
	if not view.camera.current:
		view.camera.make_current()


func _add_player(display_name: String, roster: int, is_bot: bool) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.display_name = display_name
	player.controlled_locally = not is_bot
	add_child(player)
	if is_bot:
		player.brain = Bot.new(player, game)
		player.add_child(player.brain)
	game.add_player(player, roster)
	return player
