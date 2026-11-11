extends TestCase
## Bots driving real players through the real house and match.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var house: House
var hostage: Hostage
var game: Match
var results: Array = []


func _ready() -> void:
	Cfg.setup_time = 0.5
	Cfg.round_end_time = 0.3
	house = House.new()
	add_child(house)
	hostage = Hostage.new()
	add_child(hostage)
	game = Match.new(house, hostage)
	add_child(game)
	game.round_ended.connect(func(winner: Team.Id, reason: Match.Reason) -> void: results.append([winner, reason]))


func _add(roster: int, is_bot: bool) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	add_child(player)
	if is_bot:
		player.brain = Bot.new(player, game)
		player.add_child(player.brain)
	game.add_player(player, roster)
	return player


## Runs until a round ends or `seconds` pass. Returns the simulated time taken.
func _run_round(seconds: float) -> float:
	var ticks := 0
	var already := results.size()
	while results.size() == already and ticks < seconds * 60:
		await get_tree().physics_frame
		ticks += 1
	return ticks / 60.0


func _entry_bots_rescue_from(room_index: int) -> void:
	_add(0, true)
	_add(0, true)
	game.start_match()
	game.choose_hostage_room(room_index)
	var took := await _run_round(90.0)
	var room: String = House.HOSTAGE_ROOMS[room_index].room
	check(results == [[Team.Id.ENTRY, Match.Reason.EXTRACTED]],
			"unopposed entry bots should extract from %s within 90 s (results %s, hostage state %d at %s)"
			% [room, results, hostage.state, hostage.global_position])
	print("          %s: unopposed rescue took %.0f s" % [room, took])


func test_entry_bots_rescue_from_kitchen() -> void:
	await _entry_bots_rescue_from(0)


func test_entry_bots_rescue_from_study() -> void:
	await _entry_bots_rescue_from(1)


func test_entry_bots_rescue_from_master() -> void:
	await _entry_bots_rescue_from(2)


func test_entry_bots_rescue_from_kids() -> void:
	await _entry_bots_rescue_from(3)


func test_suspect_bots_take_up_posts_in_whichever_room_holds_the_hostage() -> void:
	Cfg.setup_time = 200.0
	var guards: Array[Player] = [_add(1, true), _add(1, true)]
	game.start_match()
	for room_index in House.HOSTAGE_ROOMS.size():
		game.choose_hostage_room(room_index)
		await wait(25.0)
		var room: Dictionary = House.HOSTAGE_ROOMS[room_index]
		for i in guards.size():
			var post: Vector3 = room.posts[i]
			check(guards[i].global_position.distance_to(post) < 0.6,
					"guard %d should reach its %s post (at %s)" % [i, room.room, guards[i].global_position])


func test_bots_forget_their_route_when_a_new_round_starts() -> void:
	Cfg.setup_time = 200.0
	var guards: Array[Player] = [_add(1, true), _add(1, true)]
	var room: Dictionary = House.HOSTAGE_ROOMS[3]
	for round_index in 2:
		game.start_match()
		game.choose_hostage_room(3)  # same room both times
		await wait(25.0)
		for i in guards.size():
			var post: Vector3 = room.posts[i]
			check(guards[i].global_position.distance_to(post) < 0.6,
					"round %d: guard %d should walk to its post again (at %s)" % [round_index + 1, i, guards[i].global_position])


func test_bot_needs_its_reaction_time_then_shoots_what_it_sees() -> void:
	Cfg.bot_reaction_time = 0.5
	Cfg.round_end_time = 100.0
	var guard := _add(1, true)
	var operator := _add(0, false)
	game.start_match()
	await wait(Cfg.setup_time + 0.1)
	# Out on the lawn, guard facing the operator 6 m away.
	guard.respawn(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 14)))
	operator.respawn(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 8)))
	await wait(0.4)
	check_near(operator.health, Cfg.max_health, 0.01, "no shots inside the reaction time")
	await wait(4.0)
	check(operator.is_dead, "bot downs a stationary enemy in the open (health %.0f)" % operator.health)
	check(results == [[Team.Id.SUSPECTS, Match.Reason.ENTRY_DOWN]], "which ends the round: %s" % [results])


func test_bot_does_not_see_behind_itself() -> void:
	var guard := _add(1, true)
	var operator := _add(0, false)
	game.start_match()
	await wait(Cfg.setup_time + 0.1)
	# The guard heads north toward the house; the operator stands behind it.
	guard.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 0, 14)))
	operator.respawn(Transform3D(Basis.IDENTITY, Vector3(0, 0, 20)))
	await wait(1.5)
	check_near(operator.health, Cfg.max_health, 0.01, "an enemy outside the field of view is not engaged")


func test_bot_holds_fire_when_the_hostage_is_in_the_way() -> void:
	var guard := _add(1, true)
	var operator := _add(0, false)
	game.start_match()
	await wait(Cfg.setup_time + 0.1)
	var no_route: Array[Vector3] = []
	guard.respawn(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 14)))
	hostage.place(Vector3(-10, 0, 10), no_route)
	operator.respawn(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 9.3)))
	operator.input.crouch = true
	await wait(8.0)
	check(hostage.state == Hostage.State.HELD, "bot never shoots the hostage to get at an enemy")
	check(results.is_empty(), "round is still live: %s" % [results])


func test_four_bots_play_a_whole_match() -> void:
	Cfg.setup_time = 2.0
	Cfg.round_time = 120.0
	Cfg.match_end_time = 1000.0
	for roster: int in [0, 0, 1, 1]:
		_add(roster, true)
	game.start_match()
	var ticks := 0
	while game.phase != Match.Phase.MATCH_END and ticks < 700 * 60:
		await get_tree().physics_frame
		ticks += 1
	check(game.phase == Match.Phase.MATCH_END, "match should finish (round %d, scores %s)" % [game.board.round_number, game.board.scores])
	var scores := game.board.scores
	check(maxi(scores[0], scores[1]) == Cfg.rounds_to_win, "winner has exactly %d: %s" % [Cfg.rounds_to_win, scores])
	check(scores[0] + scores[1] == results.size() and results.size() <= 5, "one point per round, at most 5 rounds")
	var summary: Array[String] = []
	for result: Array in results:
		summary.append("%s (%s)" % [Team.NAMES[result[0]], Match.REASON_TEXT[result[1]]])
	print("          match %d-%d in %.0f s: %s" % [scores[0], scores[1], ticks / 60.0, ", ".join(summary)])
