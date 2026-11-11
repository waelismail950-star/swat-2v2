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
	# Tests that are not about gadgets want guards who go straight to their posts.
	Cfg.bot_wedge_chance = 0.0
	Cfg.bot_alarm_chance = 0.0
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
			var post: Vector3 = room.layouts[game.post_layout][i]
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
			var post: Vector3 = room.layouts[game.post_layout][i]
			check(guards[i].global_position.distance_to(post) < 0.6,
					"round %d: guard %d should walk to its post again (at %s)" % [round_index + 1, i, guards[i].global_position])


func _duel(guard_yaw: float, seconds: float) -> Player:
	Cfg.round_end_time = 100.0
	var guard := _add(1, true)
	var operator := _add(0, false)
	game.start_match()
	await wait(Cfg.setup_time + 0.1)
	guard.respawn(Transform3D(Basis(Vector3.UP, guard_yaw), Vector3(-10, 0, 14)))
	operator.respawn(Transform3D(Basis.IDENTITY, Vector3(-10, 0, 8)))   # 6 m north of the guard
	await wait(seconds)
	return operator


func test_a_guard_already_aimed_at_you_shoots_almost_at_once() -> void:
	Cfg.bot_reaction_time = 1.0
	Cfg.bot_preaim_reaction_time = 0.12
	var operator := await _duel(0.0, 0.4)   # yaw 0 faces north, straight at the operator
	check(operator.health < Cfg.max_health, "stepping into a held angle is punished within 0.4 s (health %.0f)" % operator.health)
	await wait(2.0)
	check(operator.is_dead, "and shotgun at 6 m ends it (health %.0f)" % operator.health)


func test_a_guard_who_has_to_turn_takes_the_full_reaction_time() -> void:
	Cfg.bot_reaction_time = 0.8
	Cfg.bot_preaim_reaction_time = 0.12
	var operator := await _duel(PI / 2, 0.6)   # facing west, operator is 90 degrees off to the right
	check_near(operator.health, Cfg.max_health, 0.01, "no shot yet: it is still turning and reacting (health %.0f)" % operator.health)
	await wait(5.0)
	check(operator.is_dead, "but it gets there (health %.0f)" % operator.health)


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


func _foyer_door_of(room_index: int) -> Array:
	return house.doors_of(House.HOSTAGE_ROOMS[room_index].room)


func test_suspect_bots_sometimes_wedge_a_door_and_set_an_alarm_during_setup() -> void:
	Cfg.bot_wedge_chance = 1.0
	Cfg.bot_alarm_chance = 1.0
	Cfg.setup_time = 40.0
	var guards: Array[Player] = [_add(1, true), _add(1, true)]
	game.start_match()
	game.choose_hostage_room(0)   # Kitchen: two doors
	await wait(25.0)
	var doors := _foyer_door_of(0)
	var wedged := doors.filter(func(d: Door) -> bool: return d.wedged)
	var alarmed := doors.filter(func(d: Door) -> bool: return d.alarm_side != 0.0)
	check(wedged.size() == 1, "one door of the room is wedged: %s" % [doors.map(func(d: Door) -> bool: return d.wedged)])
	check(alarmed.size() == 1, "one door has a trip alarm")
	check(wedged.size() == 1 and wedged[0].state == Door.State.CLOSED, "the wedged door is shut")
	if alarmed.size() == 1:
		check(game.house.region_at(alarmed[0].side_point(alarmed[0].alarm_side, 1.0, 0.1)) == "Kitchen", "the alarm is on the room side, where Entry will step")
	var layout: Array = House.HOSTAGE_ROOMS[0].layouts[game.post_layout]
	for i in guards.size():
		check(guards[i].global_position.distance_to(layout[i]) < 0.6, "guard %d is at its post afterwards (at %s)" % [i, guards[i].global_position])
	check(guards[0].gadget_charges[0] == Cfg.gadget_charges.wedge - 1 and guards[1].gadget_charges[1] == Cfg.gadget_charges.alarm - 1, "charges were spent")


func test_with_the_chances_at_zero_bots_place_nothing() -> void:
	Cfg.setup_time = 40.0
	_add(1, true)
	_add(1, true)
	game.start_match()
	game.choose_hostage_room(0)
	await wait(20.0)
	for door: Door in _foyer_door_of(0):
		check(not door.wedged and door.alarm_side == 0.0, "%s is clean" % door.door_name)


func test_guards_vary_their_positions_from_round_to_round() -> void:
	Cfg.round_end_time = 0.1
	_add(1, true)
	_add(1, true)
	_add(0, false)
	var seen := {}
	for round_index in 12:
		game.start_match()
		seen[game.post_layout] = true
	check(seen.size() == House.GUARD_LAYOUTS, "every layout came up over 12 rounds: %s" % [seen.keys()])


func test_entry_bots_force_a_wedged_door_and_still_rescue() -> void:
	_add(0, true)
	_add(0, true)
	game.start_match()
	game.choose_hostage_room(3)   # Kids: one door, so wedging it seals the room
	var door: Door = house.doors["Hall-Kids"]
	door.set_wedged(true)
	var took := await _run_round(120.0)
	check(results == [[Team.Id.ENTRY, Match.Reason.EXTRACTED]], "unopposed entry bots get through a wedged door: %s" % [results])
	check(not door.wedged, "by forcing it")
	check(took > Cfg.wedge_force_time + 10.0, "which costs them at least the %.0f s it takes to force (rescue took %.0f s)" % [Cfg.wedge_force_time, took])


func test_guards_swing_to_cover_a_door_when_an_alarm_goes_off() -> void:
	Cfg.setup_time = 200.0
	var guard := _add(1, true)
	game.start_match()
	game.choose_hostage_room(0)
	await wait(20.0)
	var far_door: Door = house.doors["Living-Kitchen"]
	guard.brain.hear_alarm(far_door)
	await wait(1.5)
	var to := far_door.side_point(0.0, 0.0, 1.4) - guard.camera.global_position
	check(rad_to_deg((-guard.camera.global_basis.z).angle_to(to)) < 10.0, "the guard is looking at the door that went off")


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
