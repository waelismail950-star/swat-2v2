extends TestCase
## A real house, hostage and match with four code-driven players (no bots).
## Rosters: a0, a1 start as Entry; b0, b1 start as Suspects.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var house: House
var hostage: Hostage
var game: Match
var a0: Player
var a1: Player
var b0: Player
var b1: Player
var results: Array = []


func _ready() -> void:
	Cfg.setup_time = 0.5
	Cfg.round_time = 4.0
	Cfg.round_end_time = 0.3
	Cfg.match_end_time = 0.5
	house = House.new()
	add_child(house)
	hostage = Hostage.new()
	add_child(hostage)
	game = Match.new(house, hostage)
	add_child(game)
	a0 = _add(0)
	a1 = _add(0)
	b0 = _add(1)
	b1 = _add(1)
	game.round_ended.connect(func(winner: Team.Id, reason: Match.Reason) -> void: results.append([winner, reason]))
	game.start_match()


func _add(roster: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	add_child(player)
	game.add_player(player, roster)
	return player


func _down(player: Player, by: Player = null) -> void:
	player.take_hit(10000.0, Hitbox.Zone.BODY, by)


func _go_live() -> void:
	await wait(Cfg.setup_time + 0.1)


func _next_round() -> void:
	await wait(Cfg.round_end_time + 0.1)


func test_setup_phase_assigns_sides_and_locks_everything_down() -> void:
	check(game.phase == Match.Phase.SETUP, "match starts in setup")
	check(a0.team == Team.Id.ENTRY and a1.team == Team.Id.ENTRY, "roster 0 starts as Entry")
	check(b0.team == Team.Id.SUSPECTS and b1.team == Team.Id.SUSPECTS, "roster 1 starts as Suspects")
	check(a0.arsenal.weapon().id == "carbine" and b0.arsenal.weapon().id == "shotgun", "side loadouts")
	check(a0.global_position.distance_to(House.ENTRY_SPAWNS[0]) < 0.5, "entry spawns outside")
	check(a0.global_position.distance_to(a1.global_position) > 1.0, "teammates do not spawn inside each other")
	check(house.region_at(b0.global_position) == "Foyer", "suspects spawn inside")
	check(house.doors["Front Door"].locked and house.doors["Deck Door"].locked, "exterior doors are locked")
	check(not house.doors["Foyer-Living"].locked, "interior doors are not")
	check(a0.arsenal.safe and b0.arsenal.safe, "weapons are safe during setup")
	check(hostage.state == Hostage.State.HELD, "hostage is held")
	var spot: Vector3 = House.HOSTAGE_ROOMS[game.hostage_room].spot
	check(hostage.global_position.distance_to(spot) < 0.3, "hostage is at its room's spot")
	check(not hostage.path.is_empty(), "hostage has a route out")


func test_suspect_moves_the_hostage_during_setup_only() -> void:
	Cfg.setup_time = 3.0
	game.start_match()
	var target_room := (game.hostage_room + 1) % House.HOSTAGE_ROOMS.size()
	var spot := house.hostage_spots[target_room]

	# Stand 1.3 m from the marker, on the side facing the middle of the house.
	var inward := Vector3(-spot.global_position.x, 0, -spot.global_position.z).normalized()
	var stand := Transform3D(Basis.IDENTITY, spot.global_position + inward * 1.3)
	var away := Transform3D(Basis.IDENTITY, Vector3(0, 0, 12))

	# An Entry player pressing the marker does nothing.
	a0.respawn(stand)
	await look_at_point(a0, spot.global_position + Vector3.UP * 0.5)
	check(spot.interact_prompt(a0) == "", "entry gets no prompt")
	a0.press_interact()
	check(game.hostage_room != target_room, "entry cannot move the hostage")
	a0.respawn(away)

	b0.respawn(stand)
	await look_at_point(b0, spot.global_position + Vector3.UP * 0.5)
	check(b0.aimed_interactable() == spot, "the marker is under the crosshair")
	b0.press_interact()
	check(game.hostage_room == target_room, "suspect moved the hostage")
	check(hostage.global_position.distance_to(spot.global_position) < 0.3, "hostage is at the chosen marker")

	await wait(3.0)
	check(game.phase == Match.Phase.ACTION, "round is live")
	game.choose_hostage_room((target_room + 1) % House.HOSTAGE_ROOMS.size())
	check(game.hostage_room == target_room, "the room is fixed once the round is live")
	check(b0.aimed_interactable() != spot, "markers are inert once live")


func test_going_live_unlocks_doors_and_weapons() -> void:
	await _go_live()
	check(game.phase == Match.Phase.ACTION, "live after setup time")
	check(not house.doors["Front Door"].locked and not house.doors["Deck Door"].locked, "exterior doors unlock")
	check(not a0.arsenal.safe and not b0.arsenal.safe, "weapons are hot")
	check_near(game.time_left, Cfg.round_time, 0.2, "round clock starts")


func test_clock_running_out_is_a_suspect_win() -> void:
	await _go_live()
	await wait(Cfg.round_time + 0.1)
	check(results == [[Team.Id.SUSPECTS, Match.Reason.TIME_UP]], "time up: %s" % [results])
	check(game.board.scores == [0, 1], "suspect roster scores")
	check(a0.arsenal.safe, "weapons go safe at round end")


func test_both_entry_down_is_a_suspect_win() -> void:
	await _go_live()
	_down(a0, b0)
	check(results.is_empty(), "one operator down is not the end")
	_down(a1, b0)
	check(results == [[Team.Id.SUSPECTS, Match.Reason.ENTRY_DOWN]], "entry eliminated: %s" % [results])


func test_both_suspects_down_is_an_entry_win() -> void:
	await _go_live()
	_down(b0, a0)
	_down(b1, a0)
	check(results == [[Team.Id.ENTRY, Match.Reason.SUSPECTS_DOWN]], "suspects eliminated: %s" % [results])
	check(game.board.scores == [1, 0], "entry roster scores")


func test_whoever_shoots_the_hostage_loses() -> void:
	await _go_live()
	hostage.take_hit(1.0, Hitbox.Zone.BODY, a0)
	check(results == [[Team.Id.SUSPECTS, Match.Reason.HOSTAGE_KILLED_BY_ENTRY]], "entry shot the hostage: %s" % [results])
	await _next_round()
	await _go_live()
	hostage.take_hit(1.0, Hitbox.Zone.BODY, b1)
	check(results[1] == [Team.Id.ENTRY, Match.Reason.HOSTAGE_KILLED_BY_SUSPECTS], "suspect shot the hostage: %s" % [results])


func test_extraction_is_an_entry_win() -> void:
	Cfg.round_time = 60.0
	game.start_match()
	game.choose_hostage_room(0)  # Kitchen
	await _go_live()
	# Skip the walk: open the route, secure by hand, and stay next to the hostage.
	for door_name: String in ["Kitchen-Foyer", "Front Door"]:
		house.doors[door_name].interact(Door.Action.TOGGLE_OPEN, hostage.global_position)
	hostage.on_interact_hold(a0, Cfg.hostage_secure_time)
	check(hostage.state == Hostage.State.FOLLOWING, "secured")
	for i in 40 * 60:
		if not results.is_empty():
			break
		a0.global_position = hostage.global_position + Vector3(0.8, 0, 0)
		a0.velocity = Vector3.ZERO
		await get_tree().physics_frame
	check(results == [[Team.Id.ENTRY, Match.Reason.EXTRACTED]], "extracted: %s" % [results])
	check(hostage.global_position.distance_to(House.EXTRACTION) < 0.5, "hostage reached the extraction point")


func test_only_the_first_result_counts() -> void:
	await _go_live()
	_down(b0, a0)
	_down(b1, a0)
	_down(a0, b0)
	_down(a1, b0)
	hostage.take_hit(1.0, Hitbox.Zone.BODY, a0)
	check(results.size() == 1 and game.board.scores == [1, 0], "nothing after the round ends changes the score")


func test_next_round_resets_the_world() -> void:
	await _go_live()
	house.doors["Front Door"].interact(Door.Action.TOGGLE_OPEN, a0.global_position)
	a0.arsenal.weapon().ammo = 3
	_down(b0, a0)
	_down(b1, a0)
	await _next_round()
	check(game.phase == Match.Phase.SETUP and game.board.round_number == 2, "round 2 setup")
	check(not b0.is_dead and not b1.is_dead and b0.health == Cfg.max_health, "everyone is back up")
	check(a0.arsenal.weapon().ammo == Cfg.weapons.carbine.mag, "ammo is refilled")
	check(house.doors["Front Door"].state == Door.State.CLOSED and house.doors["Front Door"].locked, "doors are shut and locked again")
	check(hostage.state == Hostage.State.HELD, "hostage is held again")
	check(a0.global_position.distance_to(House.ENTRY_SPAWNS[0]) < 0.5, "players are back at spawn")


func test_sides_swap_after_round_two() -> void:
	for round_index in 2:
		await _go_live()
		_down(a0, b0)
		_down(a1, b0)
		await _next_round()
	check(game.board.round_number == 3 and game.board.scores == [0, 2], "two suspect wins for roster 1")
	check(a0.team == Team.Id.SUSPECTS and b0.team == Team.Id.ENTRY, "sides have swapped")
	check(a0.arsenal.weapon().id == "shotgun" and b0.arsenal.weapon().id == "carbine", "loadouts follow the side")
	check(house.region_at(a0.global_position) == "Foyer", "new suspects spawn inside")
	check(b0.global_position.distance_to(House.ENTRY_SPAWNS[0]) < 0.5, "new entry spawns outside (%s)" % b0.global_position)
	await wait(0.3)
	check(b0.global_position.distance_to(House.ENTRY_SPAWNS[0]) < 0.5 and a0.velocity.length() < 0.01,
			"nobody is flung by the swap (%s)" % b0.global_position)


func test_three_wins_end_the_match_and_a_new_one_starts() -> void:
	for round_index in 3:
		await _go_live()
		for suspect in game.players_on(Team.Id.SUSPECTS):
			_down(suspect, a0)
		await _next_round()
	# Rounds 1-2: roster 0 wins as Entry. Round 3: roster 1 wins as Entry.
	check(game.board.scores == [2, 1], "score after three entry wins across the swap: %s" % [game.board.scores])
	await _go_live()
	for operator in game.players_on(Team.Id.ENTRY):
		_down(operator, a0)
	await _next_round()
	check(game.phase == Match.Phase.MATCH_END, "3 wins ends the match (phase %d)" % game.phase)
	check(game.board.scores == [3, 1] and game.board.winning_roster() == 0, "roster 0 wins 3-1")
	await wait(Cfg.match_end_time + 0.1)
	check(game.phase == Match.Phase.SETUP and game.board.scores == [0, 0] and game.board.round_number == 1,
			"a fresh match starts")
	check(a0.team == Team.Id.ENTRY, "sides are back to the starting assignment")
