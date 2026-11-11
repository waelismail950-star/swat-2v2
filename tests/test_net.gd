extends TestCase
## A host and a client running in this one process. Each lives in its own viewport with
## its own physics world and its own network connection, so they only meet over the wire.
## The host is on roster 0 (Entry first), the client on roster 1 (Suspects first).

static var _next_port := 24700

var host: Session
var client: Session
var port := 0


func _ready() -> void:
	Cfg.setup_time = 1.0
	Cfg.round_time = 60.0
	Cfg.round_end_time = 1.0
	_next_port += 1
	port = _next_port
	host = _instance("Host")
	client = _instance("Client")


func cleanup() -> void:
	for session: Session in [client, host]:
		session.leave()
		get_tree().set_multiplayer(null, session.get_parent().get_path())


func _instance(label: String) -> Session:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var session := Session.new()
	session.name = "Session"
	viewport.add_child(session)
	return session


func _connect_both() -> void:
	check(host.host("Hana", port) == OK, "host opens a server")
	check(client.join("127.0.0.1", "Cal", port) == OK, "client starts connecting")
	for i in 300:
		if host.members.size() == 2 and client.members.size() == 2:
			return
		await get_tree().physics_frame
	check(false, "client never appeared in the lobby (host sees %d, client sees %d)" % [host.members.size(), client.members.size()])


## Connects, starts the match and waits until both sides are in setup.
func _start_match(bots_think := false) -> void:
	await _connect_both()
	await _begin(bots_think)


## Starts the match from the lobby and waits until both sides are in setup.
## Bots stand idle unless `bots_think`, so they cannot shoot the players under test.
func _begin(bots_think := false) -> void:
	host.start_match()
	if not bots_think:
		for player: Player in host.world.players.values():
			player.brain = null
			player.input = PlayerInput.new()   # drop whatever the bot was pressing
	for i in 300:
		if client.world != null and client.world.game.phase == Match.Phase.SETUP:
			break
		await get_tree().physics_frame
	check(client.world != null and client.world.game.phase == Match.Phase.SETUP, "client reached setup")
	# The test drives both human players from code, not from this machine's keyboard.
	host.world.local_player.controlled_locally = false
	client.world.local_player.controlled_locally = false
	await wait(0.2)


## Lobby step: the client takes roster 0 (Entry first) and the host roster 1.
func _swap_rosters() -> void:
	client.switch_roster()
	await wait(0.2)
	host.switch_roster()
	await wait(0.2)
	check(client.local_roster() == 0 and host.local_roster() == 1,
			"rosters swapped (client %d, host %d)" % [client.local_roster(), host.local_roster()])


func _go_live() -> void:
	await wait(Cfg.setup_time + 0.3)
	check(host.world.game.phase == Match.Phase.ACTION and client.world.game.phase == Match.Phase.ACTION, "both sides are live")


## The same player as seen by the other machine.
func _on_host(player: Player) -> Player:
	return host.world.players[String(player.name)]


func _on_client(player: Player) -> Player:
	return client.world.players[String(player.name)]


## Server-side teleport; the owner follows because respawns are replicated.
func _place(player_on_host: Player, at: Vector3, yaw := 0.0) -> void:
	player_on_host.respawn(Transform3D(Basis(Vector3.UP, yaw), at))
	await wait(0.3)


func test_lobby_lists_both_players_and_lets_them_switch_roster() -> void:
	await _connect_both()
	check(host.members == client.members, "both machines see the same lobby")
	var client_id := client.multiplayer.get_unique_id()
	check(host.members[1].name == "Hana" and host.members[client_id].name == "Cal", "names arrive")
	check(host.members[1].roster == 0 and host.members[client_id].roster == 1, "players are split across rosters")

	client.switch_roster()
	await wait(0.3)
	check(host.members[client_id].roster == 0 and client.local_roster() == 0, "client moved to roster 0")
	host.switch_roster()
	await wait(0.3)
	check(client.members[1].roster == 1, "host moved to roster 1")


func test_match_start_builds_the_same_world_on_both_machines() -> void:
	await _start_match()
	var hw := host.world
	var cw := client.world
	check(hw.players.keys() == cw.players.keys() and hw.players.size() == 4, "same four players: %s vs %s" % [hw.players.keys(), cw.players.keys()])
	check(hw.local_player != null and cw.local_player != null and hw.local_player.name != cw.local_player.name, "each machine controls a different player")
	check(_on_client(hw.local_player).get_multiplayer_authority() == 1, "client knows the host owns the host's player")
	check(_on_host(cw.local_player).get_multiplayer_authority() == client.multiplayer.get_unique_id(), "host knows the client owns the client's player")
	var bots := hw.players.keys().filter(func(id: String) -> bool: return id.begins_with("Bot"))
	check(bots.size() == 2, "two bots fill the empty slots")
	check(cw.players.values().all(func(p: Player) -> bool: return p.brain == null), "bots think only on the host")

	check(cw.game.hostage_room == hw.game.hostage_room, "same hostage room")
	check(cw.hostage.global_position.distance_to(hw.hostage.global_position) < 0.1, "hostage in the same place")
	check_near(cw.game.time_left, hw.game.time_left, 0.2, "clocks agree")
	for id: String in hw.players:
		check(cw.players[id].team == hw.players[id].team, "%s is on the same side on both machines" % id)
		check(cw.players[id].global_position.distance_to(hw.players[id].global_position) < 0.3, "%s spawned in the same place" % id)
	check(cw.local_player.team == Team.Id.SUSPECTS and cw.local_player.arsenal.weapon().id == "shotgun", "client starts as a Suspect with a shotgun")
	check(cw.local_player.arsenal.safe and cw.house.doors["Front Door"].locked, "client is in setup: weapons safe, exterior locked")
	check(cw.house.hostage_spots[0].enabled, "hostage markers are live on the client during setup")


func test_movement_and_stance_replicate_both_ways() -> void:
	await _start_match()
	var mine := client.world.local_player
	var started_at := mine.global_position
	mine.input.move = Vector2(1, 0)
	await wait(1.0)
	mine.input.move = Vector2.ZERO
	mine.input.crouch = true
	mine.input.lean = -1.0
	mine.input.pitch = 0.4
	await wait(0.6)
	var seen := _on_host(mine)
	check(mine.global_position.distance_to(started_at) > 0.3, "client actually moved")
	check(mine.is_crouching() and absf(mine.lean_frac) > 0.5, "client is crouched and leaning")
	check(seen.global_position.distance_to(mine.global_position) < 0.1, "host sees the client where the client is (%s vs %s)" % [seen.global_position, mine.global_position])
	check_near(seen.crouch_frac, 1.0, 0.05, "crouch arrives")
	check_near(seen.lean_frac, mine.lean_frac, 0.05, "lean arrives")
	check(seen.head.global_position.distance_to(mine.head.global_position) < 0.1, "so the head hitbox is where the client's head is")
	check_near(seen.head.rotation.x, 0.4, 0.05, "pitch arrives")

	var hosts := host.world.local_player
	hosts.input.move = Vector2(0, -1)
	await wait(1.0)
	hosts.input.move = Vector2.ZERO
	await wait(0.4)
	check(_on_client(hosts).global_position.distance_to(hosts.global_position) < 0.1, "client sees the host where the host is")


func test_bots_on_the_host_are_visible_on_the_client() -> void:
	await _start_match(true)
	await wait(3.0)
	var bots_seen := 0
	for id: String in host.world.players:
		var real := host.world.players[id]
		if real.brain != null and real.team == Team.Id.SUSPECTS:
			bots_seen += 1
			check(real.global_position.distance_to(House.SUSPECT_SPAWNS[0]) > 1.0 and real.global_position.distance_to(House.SUSPECT_SPAWNS[1]) > 1.0, "suspect bot has walked off toward its post")
			check(client.world.players[id].global_position.distance_to(real.global_position) < 0.3, "client sees bot %s where the host has it" % id)
	check(bots_seen == 1, "one suspect bot was checked")


func test_doors_are_opened_by_the_server_and_shown_to_everyone() -> void:
	await _start_match()
	var mine := client.world.local_player
	await _place(_on_host(mine), Vector3(-0.6, 0, 2.5), PI / 2)  # facing the Foyer-Living door
	check(mine.global_position.distance_to(Vector3(-0.6, 0, 2.5)) < 0.2, "client was moved by the server's respawn")
	check(mine.aimed_interactable() == client.world.house.doors["Foyer-Living"], "door is under the client's crosshair")
	mine.press_interact()
	check(client.world.house.doors["Foyer-Living"].state == Door.State.CLOSED, "the client does not open the door itself")
	await wait(0.8)
	var host_door := host.world.house.doors["Foyer-Living"]
	var client_door := client.world.house.doors["Foyer-Living"]
	check(host_door.state == Door.State.OPEN, "server opened it")
	check(client_door.state == Door.State.OPEN, "client was told")
	check_near(client_door.angle_deg, host_door.angle_deg, 0.5, "and swung it the same way")
	check(absf(host_door.angle_deg) > 80.0, "door is actually open")

	await look_at_point(mine, client_door.panel_point())
	mine.press_crack()
	await wait(0.8)
	check(host_door.state == Door.State.CRACKED and client_door.state == Door.State.CRACKED, "crack requests work too")


func test_locked_exterior_doors_unlock_for_clients_when_the_round_goes_live() -> void:
	await _start_match()
	var mine := client.world.local_player
	await _place(_on_host(mine), Vector3(0, 0, 3.6), PI)  # inside, facing the front door
	mine.press_interact()
	await wait(0.4)
	check(host.world.house.doors["Front Door"].state == Door.State.CLOSED, "locked during setup")
	await _go_live()
	check(not client.world.house.doors["Front Door"].locked, "client knows it is unlocked")
	mine.press_interact()
	await wait(0.6)
	check(host.world.house.doors["Front Door"].state == Door.State.OPEN and client.world.house.doors["Front Door"].state == Door.State.OPEN, "opens once live")


func test_client_shots_are_resolved_by_the_server() -> void:
	Cfg.weapons.pistol.spread_deg = 0.0
	Cfg.weapons.pistol.move_spread_deg = 0.0
	await _start_match()
	await _go_live()
	var shooter := client.world.local_player          # Suspect, owned by the client
	var target := host.world.local_player             # Entry, owned by the host
	await _place(_on_host(shooter), Vector3(-12, 0, 12), 0.0)
	await _place(target, Vector3(-12, 0, 6), 0.0)
	shooter.input.weapon_slot = 1
	await wait(Cfg.weapon_swap_time + 0.2)
	var marks := []
	shooter.arsenal.hit_landed.connect(func(zone: Hitbox.Zone, killed: bool) -> void: marks.append([zone, killed]))

	await look_at_point(shooter, _on_client(target).global_position + Vector3.UP * 1.2)
	shooter.input.fire = true
	await wait(0.05)
	shooter.input.fire = false
	await wait(0.4)
	var expected: float = Cfg.max_health - Cfg.weapons.pistol.damage * Cfg.entry_body_damage_mult
	check_near(target.health, expected, 0.01, "server applied one armored pistol hit")
	check_near(_on_client(target).health, expected, 0.01, "client was told the new health")
	check(marks == [[Hitbox.Zone.BODY, false]], "client got its hit marker from the server: %s" % [marks])
	check(shooter.arsenal.weapon().ammo == Cfg.weapons.pistol.mag - 1, "client spent a round")

	await look_at_point(shooter, _on_client(target).head.global_position)
	shooter.input.fire = true
	await wait(0.05)
	shooter.input.fire = false
	await wait(0.4)
	check(target.is_dead and _on_client(target).is_dead, "headshot downs the host's player on both machines")
	check(marks.size() == 2 and marks[1] == [Hitbox.Zone.HEAD, true], "kill marker arrives: %s" % [marks])


func test_host_shots_hit_the_client_where_the_client_stands() -> void:
	Cfg.weapons.carbine.spread_deg = 0.0
	Cfg.weapons.carbine.move_spread_deg = 0.0
	await _start_match()
	await _go_live()
	var shooter := host.world.local_player
	var target := client.world.local_player
	await _place(shooter, Vector3(-12, 0, 12), 0.0)
	await _place(_on_host(target), Vector3(-12, 0, 6), 0.0)
	# The client leans; the host must aim at the leaned head to hit it.
	target.input.lean = 1.0
	await wait(0.5)
	await look_at_point(shooter, target.head.global_position)
	shooter.input.fire = true
	await wait(0.05)
	shooter.input.fire = false
	await wait(0.3)
	check(_on_host(target).is_dead and target.is_dead, "host hit the client's leaned head; client knows it is down")
	target.input.move = Vector2(1, 0)
	await wait(0.5)
	check(target.velocity.length() < 0.01, "a downed client cannot move")


func test_server_rejects_shots_that_break_the_rules() -> void:
	await _start_match()
	var shooter := client.world.local_player
	var target := host.world.local_player
	await _place(_on_host(shooter), Vector3(-12, 0, 12), 0.0)
	await _place(target, Vector3(-12, 0, 11), 0.0)
	var aim := (target.global_position + Vector3.UP * 1.2 - shooter.camera.global_position).normalized()
	var pellets: Array[Vector3] = []
	for i: int in Cfg.weapons.shotgun.pellets:
		pellets.append(aim)

	# Still in setup: the client pretends its weapon is live.
	shooter.send_shot(0, shooter.camera.global_position, pellets)
	await wait(0.3)
	check_near(target.health, Cfg.max_health, 0.01, "no shooting during setup, whatever the client says")

	await _go_live()
	shooter.send_shot(0, shooter.camera.global_position + Vector3(0, 0, -8), pellets)
	await wait(0.3)
	check_near(target.health, Cfg.max_health, 0.01, "a shot claimed from somewhere the player is not is ignored")

	var too_many := pellets.duplicate()
	too_many.append_array(pellets)
	shooter.send_shot(0, shooter.camera.global_position, too_many)
	await wait(0.3)
	check_near(target.health, Cfg.max_health, 0.01, "wrong pellet count is ignored")

	for i in 10:
		shooter.send_shot(1, shooter.camera.global_position, [aim] as Array[Vector3])
	await wait(0.3)
	var landed := roundi((Cfg.max_health - target.health) / (Cfg.weapons.pistol.damage * Cfg.entry_body_damage_mult))
	check(landed >= 1 and landed <= 3, "ten pistol shots at once: only a small burst counts (%d landed)" % landed)


func test_hostage_marker_secure_and_round_result_replicate() -> void:
	# Swap rosters in the lobby so the client plays Entry first.
	await _connect_both()
	await _swap_rosters()
	await _begin()
	var hw := host.world
	var cw := client.world
	var operator := cw.local_player
	check(operator.team == Team.Id.ENTRY, "client is Entry")

	# Host (a Suspect) moves the hostage with a marker, through the normal interact path.
	var room := (hw.game.hostage_room + 1) % House.HOSTAGE_ROOMS.size()
	var spot := hw.house.hostage_spots[room]
	var inward := Vector3(-spot.global_position.x, 0, -spot.global_position.z).normalized()
	await _place(hw.local_player, spot.global_position + inward * 1.3)
	await look_at_point(hw.local_player, spot.global_position + Vector3.UP * 0.5)
	hw.local_player.press_interact()
	await wait(0.3)
	check(hw.game.hostage_room == room and cw.game.hostage_room == room, "client learns the new hostage room")
	check(cw.hostage.global_position.distance_to(spot.global_position) < 0.3, "and sees the hostage there")
	await _place(hw.local_player, Vector3(-20, 0, 20))

	await _go_live()
	# Client stands by the hostage and holds interact.
	await _place(_on_host(operator), spot.global_position + inward * 1.3)
	await look_at_point(operator, cw.hostage.global_position + Vector3.UP * 0.8)
	check(operator.aimed_interactable() == cw.hostage, "hostage is under the client's crosshair")
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time * 0.5)
	check(hw.hostage.secure_progress > 0.5, "server is counting the client's hold")
	check(cw.hostage.secure_progress > 0.5, "client sees the progress")
	check(hw.hostage.state == Hostage.State.HELD, "not secured yet")
	await wait(Cfg.hostage_secure_time * 0.5 + 0.5)
	operator.input.interact = false
	check(hw.hostage.state == Hostage.State.FOLLOWING, "server secured the hostage")
	check(cw.hostage.state == Hostage.State.FOLLOWING, "client sees it following")

	# A Suspect shoots the hostage: Entry wins, and both machines agree on why.
	hw.hostage.take_hit(1.0, Hitbox.Zone.BODY, hw.local_player)
	await wait(0.4)
	for game: Match in [hw.game, cw.game]:
		check(game.phase == Match.Phase.ROUND_END, "round over")
		check(game.last_winner == Team.Id.ENTRY and game.last_reason == Match.Reason.HOSTAGE_KILLED_BY_SUSPECTS, "same result")
		check(game.board.scores == [1, 0], "same score: %s" % [game.board.scores])
	check(cw.hostage.state == Hostage.State.DEAD, "client sees the hostage down")

	await wait(Cfg.round_end_time + 0.5)
	check(cw.game.board.round_number == 2 and cw.game.phase == Match.Phase.SETUP, "client follows into round 2")
	check(cw.hostage.state == Hostage.State.HELD, "hostage is reset on the client")
	check(cw.house.doors["Front Door"].locked, "doors are locked again on the client")
	check(not operator.is_dead and operator.health == Cfg.max_health, "client player is reset")


func test_letting_go_stops_the_servers_count() -> void:
	await _connect_both()
	await _swap_rosters()
	await _begin()
	await _go_live()
	var operator := client.world.local_player
	var spot: Vector3 = host.world.hostage.global_position
	var inward := Vector3(-spot.x, 0, -spot.z).normalized()
	await _place(_on_host(operator), spot + inward * 1.3)
	await look_at_point(operator, client.world.hostage.global_position + Vector3.UP * 0.8)
	operator.input.interact = true
	await wait(1.0)
	operator.input.interact = false
	await wait(0.4)
	check_near(host.world.hostage.secure_progress, 0.0, 0.001, "server resets progress when the client lets go")
	await wait(Cfg.hostage_secure_time)
	check(host.world.hostage.state == Hostage.State.HELD, "and never secures")


func _tap_gadget(player: Player, slot: int) -> void:
	if slot == 0:
		player.input.gadget_1 = true
	else:
		player.input.gadget_2 = true
	await wait(0.05)
	player.input.gadget_1 = false
	player.input.gadget_2 = false
	await wait(0.3)


func test_suspect_gadgets_placed_by_a_client_are_real_on_the_server() -> void:
	await _start_match()
	var suspect := client.world.local_player
	var host_door := host.world.house.doors["Foyer-Living"]
	var client_door := client.world.house.doors["Foyer-Living"]
	var client_alarms: Array[String] = []
	client.world.gadgets.alarm_raised.connect(func(d: Door) -> void: client_alarms.append(d.door_name))

	await _place(_on_host(suspect), Vector3(-3.3, 0, 2.5), -PI / 2)   # in the Living room, facing the door
	await _tap_gadget(suspect, 0)
	check(host_door.wedged and client_door.wedged, "wedge is on the door on both machines")
	await _tap_gadget(suspect, 1)
	check(host_door.alarm_side != 0.0 and client_door.alarm_side == host_door.alarm_side, "trip alarm too, on the same side")
	var left := [Cfg.gadget_charges.wedge - 1, Cfg.gadget_charges.alarm - 1]
	check(_on_host(suspect).gadget_charges == left and suspect.gadget_charges == left,
			"charges agree: host %s, client %s" % [_on_host(suspect).gadget_charges, suspect.gadget_charges])

	await _go_live()
	await _place(_on_host(suspect), Vector3(-20, 0, 20))   # out of the doorway
	# The host's Entry player forces the wedge, opens the door and walks into the alarm.
	var operator := host.world.local_player
	await _place(operator, Vector3(-0.7, 0, 2.5), PI / 2)
	operator.input.interact = true
	await wait(Cfg.wedge_force_time + 0.3)
	operator.input.interact = false
	await wait(0.2)
	check(not host_door.wedged and not client_door.wedged, "forced wedge disappears for the client too")
	operator.press_interact()
	await wait(0.6)
	check(await walk_to(operator, Vector3(-4.5, 0, 2.5), 4.0), "operator walks in")
	await wait(0.3)
	check(client_alarms == ["Foyer-Living"], "the client is alerted: %s" % [client_alarms])
	check(client_door.alarm_side == 0.0, "and sees the alarm gone")


func test_flashbang_thrown_by_the_host_blinds_the_client() -> void:
	await _start_match()
	await _go_live()
	var thrower := host.world.local_player
	var victim := client.world.local_player
	await _place(thrower, Vector3(-12, 0, 20), 0.0)
	await _place(_on_host(victim), Vector3(-12, 0, 10), PI)
	await _tap_gadget(thrower, 0)
	await wait(0.4)
	var seen := client.world.get_children().filter(func(n: Node) -> bool: return n is Flashbang)
	check(seen.size() == 1, "client sees the grenade in flight")
	var real := host.world.get_children().filter(func(n: Node) -> bool: return n is Flashbang)
	if seen.size() == 1 and real.size() == 1:
		check(seen[0].global_position.distance_to(real[0].global_position) < 0.5, "where the host has it")
	# Look at wherever it ends up, so the flash is not weakened by facing away.
	await wait(Cfg.flash_fuse - 1.0)
	if real.size() == 1 and is_instance_valid(real[0]):
		await look_at_point(victim, real[0].global_position)
	await wait(0.6)
	check(victim.flash_left > 0.5, "the client's own player is blinded (%.2f s)" % victim.flash_left)
	check(_on_host(victim).flash_left > 0.5, "and the host knows it")
	check(client.world.get_children().filter(func(n: Node) -> bool: return n is Flashbang and not n.is_queued_for_deletion()).is_empty(),
			"the grenade is gone on the client")
	check(_on_client(thrower).gadget_charges[0] == Cfg.gadget_charges.flashbang - 1, "client sees the host's remaining charges")


func test_client_loadout_choice_and_door_camera() -> void:
	await _connect_both()
	await _swap_rosters()
	await _begin()
	var operator := client.world.local_player
	check(operator.gadgets == ["flashbang", "door_camera"], "client starts with the default Entry kit")
	operator.input.next_loadout = true
	await wait(0.05)
	operator.input.next_loadout = false
	await wait(0.3)
	check(_on_host(operator).gadgets == ["flashbang", "breach"], "server changed the client's kit: %s" % [_on_host(operator).gadgets])
	check(operator.gadgets == ["flashbang", "breach"], "client was told: %s" % [operator.gadgets])
	for i in 2:
		operator.input.next_loadout = true
		await wait(0.05)
		operator.input.next_loadout = false
		await wait(0.3)
	check(operator.gadgets == ["flashbang", "door_camera"], "back to the camera kit: %s" % [operator.gadgets])

	await _go_live()
	var host_door := host.world.house.doors["Foyer-Living"]
	var target := host.world.local_player
	await _place(target, Vector3(-3.3, 0, 2.5), -PI / 2)             # host's Suspect just inside the room
	await _place(_on_host(operator), Vector3(-0.7, 0, 2.5), PI / 2)  # client at the door
	operator.input.gadget_2 = true
	await wait(0.4)
	check(operator.peek_door == client.world.house.doors["Foyer-Living"], "client is looking under the door")
	check(_on_host(operator).peek_door == host_door, "server knows")
	check(host_door.scope_side != 0.0, "the lens is visible on the host")
	check(operator.active_camera().is_position_in_frustum(_on_client(target).head.global_position), "the client can see the host's player through it")

	var pellet: Array[Vector3] = [Vector3(-1, 0, 0)]
	operator.send_shot(0, operator.camera.global_position, pellet)
	await wait(0.3)
	check(operator.arsenal.safe == false and target.health == Cfg.max_health, "the server ignores shots from a player using the camera")

	operator.input.gadget_2 = false
	await wait(0.4)
	check(_on_host(operator).peek_door == null and host_door.scope_side == 0.0, "putting it away removes the lens on the host")


func test_client_hears_what_the_host_does() -> void:
	await _start_match()
	await _go_live()
	var heard: Array[String] = []
	client.world.sounds.emitted.connect(func(kind: String, _at: Vector3) -> void: heard.append(kind))
	var operator := host.world.local_player
	var host_door := host.world.house.doors["Foyer-Living"]

	await _place(operator, Vector3(-14, 0, 20))
	heard.clear()
	operator.input.move = Vector2(0, 1)
	await wait(2.0)
	operator.input.move = Vector2.ZERO
	check(heard.count("step_walk") >= 5, "footsteps: %s" % [heard])

	heard.clear()
	operator.input.fire = true
	await wait(0.05)
	operator.input.fire = false
	await wait(0.3)
	check(heard.has("shot_carbine"), "gunshot: %s" % [heard])

	host_door.set_wedged(true)
	await _place(operator, Vector3(-0.7, 0, 2.5), PI / 2)
	heard.clear()
	operator.input.interact = true
	await wait(1.5)
	check(heard.count("force") >= 2, "someone forcing a door: %s" % [heard])
	await wait(Cfg.wedge_force_time - 1.2)
	operator.input.interact = false
	await wait(0.2)
	heard.clear()
	operator.press_interact()
	await wait(0.4)
	check(heard.has("door_open"), "the door opening: %s" % [heard])


func test_a_client_that_leaves_is_replaced_by_a_bot() -> void:
	await _start_match()
	var id := String(client.world.local_player.name)
	check(host.world.players[id].brain == null, "a human's player has no bot brain")
	client.leave()
	await wait(1.0)
	var orphan := host.world.players[id]
	check(orphan.get_multiplayer_authority() == 1, "host takes the player over")
	check(orphan.brain != null, "and gives it a bot brain")
	check(host.members.size() == 1, "lobby list drops the client")
	var before := orphan.global_position
	await wait(3.0)
	check(orphan.global_position.distance_to(before) > 0.5, "the bot is driving it")


func test_solo_play_runs_the_same_code_offline() -> void:
	host.play_solo("Solo")
	await wait(0.3)
	check(host.world != null and host.world.players.size() == 4, "world with one human and three bots")
	check(host.world.game.phase == Match.Phase.SETUP, "match started")
	check(host.world.local_player != null and host.world.local_player.team == Team.Id.ENTRY, "the human starts as Entry")
