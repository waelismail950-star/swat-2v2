extends TestCase
## Hostage kneels at the origin. Its route runs 6 m along +X.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var hostage: Hostage
var events: Array[String] = []


func _ready() -> void:
	Greybox.add_box(self, Vector3(0, -0.25, 0), Vector3(60, 0.5, 60), Color.GRAY)
	hostage = Hostage.new()
	add_child(hostage)
	var route: Array[Vector3] = [Vector3(3, 0, 0), Vector3(6, 0, 0)]
	hostage.place(Vector3.ZERO, route)
	hostage.secured.connect(func(_by: Player) -> void: events.append("secured"))
	hostage.killed.connect(func(_by: Node) -> void: events.append("killed"))
	hostage.extracted.connect(func() -> void: events.append("extracted"))


func _spawn(at: Vector3, team: Team.Id) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	player.position = at
	add_child(player)
	player.assign_team(team)
	for id: String in Cfg.weapons:
		Cfg.weapons[id].spread_deg = 0.0
	return player


func _aim_at_hostage(player: Player) -> void:
	await look_at_point(player, hostage.global_position + Vector3.UP * 0.8)


func test_holding_interact_secures_after_the_full_time() -> void:
	var operator := _spawn(Vector3(0, 0, 1.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	check(operator.aimed_interactable() == hostage, "hostage is under the crosshair")
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time - 0.3)
	check(hostage.state == Hostage.State.HELD, "not secured early")
	check(hostage.secure_progress > 1.0, "progress is building")
	await wait(0.5)
	check(hostage.state == Hostage.State.FOLLOWING and events == ["secured"], "secured after the full hold")


func test_releasing_the_key_loses_progress() -> void:
	var operator := _spawn(Vector3(0, 0, 1.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time * 0.6)
	operator.input.interact = false
	await wait(0.1)
	check_near(hostage.secure_progress, 0.0, 0.001, "progress resets on release")
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time * 0.6)
	check(hostage.state == Hostage.State.HELD, "two partial holds do not add up")


func test_looking_away_loses_progress() -> void:
	var operator := _spawn(Vector3(0, 0, 1.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	operator.input.interact = true
	await wait(1.0)
	await look_at_point(operator, Vector3(5, 1, 1.4))
	await wait(0.1)
	check_near(hostage.secure_progress, 0.0, 0.001, "progress resets when the crosshair leaves")


func test_suspects_and_distant_operators_cannot_secure() -> void:
	var suspect := _spawn(Vector3(0, 0, 1.4), Team.Id.SUSPECTS)
	var far_operator := _spawn(Vector3(0, 0, 4.0), Team.Id.ENTRY)
	await _aim_at_hostage(suspect)
	await _aim_at_hostage(far_operator)
	suspect.input.interact = true
	far_operator.input.interact = true
	await wait(Cfg.hostage_secure_time + 0.5)
	check(hostage.state == Hostage.State.HELD, "still held")
	check(hostage.interact_prompt(suspect) == "", "suspects get no secure prompt")


func test_secured_hostage_walks_only_while_escorted() -> void:
	var operator := _spawn(Vector3(0, 0, 1.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time + 0.1)
	operator.input.interact = false
	await wait(1.0)
	var walked := hostage.global_position.x
	check(walked > 1.0, "hostage walks its route while the escort is close (x=%.2f)" % walked)

	# Escort runs off the other way: the hostage stops.
	check(await walk_to(operator, Vector3(-8, 0, 1.4), 6.0), "escort leaves")
	var stopped_at := hostage.global_position.x
	await wait(1.0)
	check_near(hostage.global_position.x, stopped_at, 0.01, "hostage waits without an escort")
	check(stopped_at < 5.0, "hostage did not finish alone (x=%.2f)" % stopped_at)

	# Escort returns: it carries on and is extracted at the end of the route.
	check(await walk_to(operator, Vector3(5, 0, 1.4), 8.0), "escort returns")
	await wait(3.0)
	check(hostage.state == Hostage.State.EXTRACTED and events == ["secured", "extracted"], "extracted at the last waypoint")


func test_a_downed_escort_does_not_count() -> void:
	var operator := _spawn(Vector3(0, 0, 1.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	operator.input.interact = true
	await wait(Cfg.hostage_secure_time + 0.1)
	operator.take_hit(1000.0, Hitbox.Zone.BODY, null)
	var stopped_at := hostage.global_position.x
	await wait(1.0)
	check_near(hostage.global_position.x, stopped_at, 0.01, "hostage does not follow a downed operator")


func test_one_bullet_kills_the_hostage_and_names_the_shooter() -> void:
	var shooter := _spawn(Vector3(0, 0, 5), Team.Id.ENTRY)
	var report := {}
	hostage.killed.connect(func(by: Node) -> void: report.by = by)
	await _aim_at_hostage(shooter)
	shooter.input.fire = true
	await wait(0.05)
	shooter.input.fire = false
	check(hostage.state == Hostage.State.DEAD, "a single direct hit is fatal")
	check(report.get("by") == shooter, "the shooter is reported")
	check(events == ["killed"], "killed fires once")


func test_hostage_shields_whoever_stands_behind_it() -> void:
	var shooter := _spawn(Vector3(0, 0, 5), Team.Id.ENTRY)
	var hiding := _spawn(Vector3(0, 0, -1.0), Team.Id.SUSPECTS)
	hiding.input.crouch = true
	await wait(0.4)
	await _aim_at_hostage(shooter)
	shooter.input.fire = true
	await wait(0.05)
	shooter.input.fire = false
	check(hostage.state == Hostage.State.DEAD, "the bullet stops in the hostage")
	check_near(hiding.health, Cfg.max_health, 0.01, "the player behind is untouched")


func test_hostage_does_not_block_movement() -> void:
	var walker := _spawn(Vector3(0, 0, 2), Team.Id.SUSPECTS)
	check(await walk_to(walker, Vector3(0, 0, -2), 4.0), "players pass through the hostage")


func test_place_resets_everything() -> void:
	hostage.take_hit(100.0, Hitbox.Zone.BODY, null)
	check(hostage.state == Hostage.State.DEAD, "dead")
	var route: Array[Vector3] = [Vector3(9, 0, 9)]
	hostage.place(Vector3(2, 0, 2), route)
	check(hostage.state == Hostage.State.HELD and hostage.health == Cfg.hostage_health, "held and healthy again")
	check(hostage.global_position.distance_to(Vector3(2, 0, 2)) < 0.01, "moved to the new spot")
	var operator := _spawn(Vector3(2, 0, 3.4), Team.Id.ENTRY)
	await _aim_at_hostage(operator)
	check(operator.aimed_interactable() == hostage, "can be interacted with again")
