extends Node3D
## Entry point: menu, then a match. Options after `--` on the command line skip the menu:
##   --solo             play alone with three bots
##   --host             host a game and wait in the lobby
##   --join=ADDRESS     join the game hosted at ADDRESS
##   --name=NAME        player name
##   --autostart=N      (host) start the match as soon as N humans are in the lobby
##   --autopilot        let a bot play for you
##   --quick            (host) 3 s setup, 60 s rounds, 1 s between rounds; quit when the match ends
##   --netlog           print one line of match state per second

var _options := {}
var _log_timer := 0.0
var _logged_phase := -1
var _quit_timer := 2.0

@onready var _session: Session = $Session
@onready var _menu: Menu = $Menu
@onready var _hud: Hud = $Hud


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := argument.trim_prefix("--").split("=", true, 1)
		_options[parts[0]] = parts[1] if parts.size() > 1 else ""

	_menu.session = _session
	_hud.visible = false
	_session.world_started.connect(_on_world_started)
	_session.ended.connect(_on_session_ended)
	_session.members_changed.connect(_on_members_changed)

	var player_name: String = _options.get("name", "Player")
	if _options.has("quick"):
		Cfg.setup_time = 3.0
		Cfg.round_time = 60.0
		Cfg.round_end_time = 1.0
	if _options.has("solo"):
		_session.play_solo(player_name)
	elif _options.has("host"):
		_menu.show_message("Hosting." if _session.host(player_name) == OK else "Could not host.")
	elif _options.has("join"):
		_session.join(_options.join, player_name)


func _unhandled_input(event: InputEvent) -> void:
	if _session.world == null:
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var world := _session.world
	if world == null:
		return
	# A downed player watches through a living teammate's eyes.
	var me := world.local_player
	var view := me
	if me.is_dead:
		for mate in world.game.players_on(me.team):
			if not mate.is_dead:
				view = mate
	if not view.active_camera().current:
		view.active_camera().make_current()

	if _options.has("netlog"):
		_log_timer -= delta
		if _log_timer <= 0.0 or world.game.phase != _logged_phase:
			_log_timer = 1.0
			_logged_phase = world.game.phase
			_print_state(world)
	# Scripted runs: stay on the final score for a moment so clients receive it, then exit.
	if _options.has("quick") and world.game.phase == Match.Phase.MATCH_END:
		_quit_timer -= delta
		if _quit_timer <= 0.0:
			get_tree().quit()


func _on_members_changed() -> void:
	var wanted := int(_options.get("autostart", "0"))
	if wanted > 0 and _session.is_host() and _session.in_lobby() and _session.members.size() >= wanted:
		_session.start_match()


func _on_world_started(world: World) -> void:
	_menu.visible = false
	_hud.visible = true
	_hud.game = world.game
	_hud.gadgets = world.gadgets
	_hud.player = world.local_player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _options.has("autopilot"):
		world.local_player.controlled_locally = false
		world.give_brain(world.local_player)


func _on_session_ended(_reason: String) -> void:
	_menu.visible = true
	_hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _options.has("join") and _options.has("netlog"):
		get_tree().quit()  # scripted client: the host is gone, nothing left to do


func _print_state(world: World) -> void:
	var game := world.game
	var doors_open := world.house.doors.values().filter(func(d: Door) -> bool: return d.state != Door.State.CLOSED).size()
	var health: Array[String] = []
	for id: String in world.players:
		health.append("%s=%d" % [id, ceili(world.players[id].health)])
	print("NET round=%d phase=%s scores=%s room=%d hostage=%s doors_open=%d %s" % [
		game.board.round_number, Match.Phase.keys()[game.phase], game.board.scores, game.hostage_room,
		Hostage.State.keys()[world.hostage.state], doors_open, " ".join(health)])
