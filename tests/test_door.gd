extends TestCase
## A wall along X at z = 0 with a 1 m doorway centred on the origin. Hinge at x = -0.5.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

const SOUTH := Vector3(0, 0, 1.5)   # +Z side of the door
const NORTH := Vector3(0, 0, -1.5)

var door: Door


func _ready() -> void:
	Greybox.add_box(self, Vector3(0, -0.25, 0), Vector3(30, 0.5, 30), Color.GRAY)
	Greybox.add_box(self, Vector3(-5.5, 1.5, 0), Vector3(10, 3, 0.2), Color.WHITE)
	Greybox.add_box(self, Vector3(5.5, 1.5, 0), Vector3(10, 3, 0.2), Color.WHITE)
	Greybox.add_box(self, Vector3(0, 2.55, 0), Vector3(1, 0.9, 0.2), Color.WHITE)
	door = Door.new()
	door.position = Vector3(-0.5, 0, 0)
	add_child(door)


func _spawn(at: Vector3) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	player.position = at
	add_child(player)
	return player


func test_state_transitions() -> void:
	check(door.state == Door.State.CLOSED, "starts closed")
	door.interact(Door.Action.TOGGLE_OPEN, SOUTH)
	check(door.state == Door.State.OPEN, "closed -> open")
	door.interact(Door.Action.TOGGLE_CRACK, SOUTH)
	check(door.state == Door.State.CRACKED, "open -> cracked")
	door.interact(Door.Action.TOGGLE_OPEN, SOUTH)
	check(door.state == Door.State.OPEN, "cracked -> open")
	door.interact(Door.Action.TOGGLE_OPEN, SOUTH)
	check(door.state == Door.State.CLOSED, "open -> closed")
	door.interact(Door.Action.TOGGLE_CRACK, SOUTH)
	check(door.state == Door.State.CRACKED, "closed -> cracked")
	door.interact(Door.Action.TOGGLE_CRACK, SOUTH)
	check(door.state == Door.State.CLOSED, "cracked -> closed")


func test_swings_away_from_operator() -> void:
	door.interact(Door.Action.TOGGLE_OPEN, SOUTH)
	await wait(0.6)
	check_near(door.angle_deg, Cfg.door_open_angle_deg, 0.01, "opened from south swings north")
	var latch := door.to_global(Vector3(1, 1, 0).rotated(Vector3.UP, deg_to_rad(door.angle_deg)))
	check(latch.z < -0.9, "panel should end up on the north side (z=%.2f)" % latch.z)

	door.interact(Door.Action.TOGGLE_OPEN, NORTH)
	await wait(0.6)
	check_near(door.angle_deg, 0.0, 0.01, "closes")

	door.interact(Door.Action.TOGGLE_OPEN, NORTH)
	await wait(0.6)
	check_near(door.angle_deg, -Cfg.door_open_angle_deg, 0.01, "opened from north swings south")


func test_closed_door_blocks_movement_and_sight() -> void:
	var player := _spawn(SOUTH)
	check(not has_line_of_sight(Vector3(0, 1.5, 1.5), Vector3(0, 1.5, -1.5)), "closed door blocks sight")
	check(not await walk_to(player, NORTH, 2.0), "closed door blocks movement")
	check(player.global_position.z > 0.2, "player stays on the near side")


func test_open_door_lets_player_through() -> void:
	var player := _spawn(SOUTH)
	door.interact(Door.Action.TOGGLE_OPEN, player.global_position)
	await wait(0.6)
	check(has_line_of_sight(Vector3(0, 1.5, 1.5), Vector3(0, 1.5, -1.5)), "open door clears sight")
	check(await walk_to(player, NORTH, 3.0), "should walk through the open door")


func test_cracked_door_gives_a_sliver_of_sight_but_no_passage() -> void:
	var player := _spawn(SOUTH)
	door.interact(Door.Action.TOGGLE_CRACK, player.global_position)
	await wait(0.4)
	check_near(door.angle_deg, Cfg.door_crack_angle_deg, 0.01, "crack angle")
	# Diagonal line through the gap at the latch side.
	check(has_line_of_sight(Vector3(0, 1.5, 1.5), Vector3(0.9, 1.5, -1.5)), "gap should give a diagonal sightline")
	check(not has_line_of_sight(Vector3(-0.3, 1.5, 1.5), Vector3(-0.3, 1.5, -1.5)), "rest of the doorway stays covered")
	check(not await walk_to(player, NORTH, 2.0), "cracked door must not be walkable")
	check(player.global_position.z > 0.0, "player stays on the near side")


func test_body_in_the_way_stops_the_door_until_it_moves() -> void:
	# Bystander stands north of the doorway, inside the arc the panel sweeps.
	var bystander := _spawn(Vector3(0.1, 0, -0.75))
	await wait(0.2)
	door.interact(Door.Action.TOGGLE_OPEN, Vector3(0, 0, 3.0))
	await wait(1.0)
	check(door.angle_deg > 5.0 and door.angle_deg < 80.0,
			"door should stop partway against the body (angle=%.1f)" % door.angle_deg)
	check(not door.is_settled(), "door is still trying to open")

	check(await walk_to(bystander, Vector3(3, 0, -3), 4.0), "bystander walks clear")
	await wait(0.6)
	check_near(door.angle_deg, Cfg.door_open_angle_deg, 0.01, "door finishes opening once clear")


func test_door_cannot_be_held_shut_by_leaning_on_it() -> void:
	var blocker := _spawn(Vector3(0, 0, -0.34))  # pressed against the north face
	await wait(0.2)
	door.interact(Door.Action.TOGGLE_OPEN, SOUTH)
	await wait(0.8)
	check_near(door.angle_deg, -Cfg.door_open_angle_deg, 0.01, "door opens toward the operator instead")
	check(blocker.global_position.z < 0.0, "blocker was not pushed through")


func test_player_operates_door_only_when_aiming_at_it_in_range() -> void:
	var player := _spawn(Vector3(0, 0, 4.0))
	await look_at_point(player, Vector3(0, 1.2, 0))
	check(player.aimed_interactable() == null, "4 m is out of reach")
	player.press_interact()
	check(door.state == Door.State.CLOSED, "pressing interact out of reach does nothing")

	check(await walk_to(player, Vector3(0, 0, 1.5), 3.0), "walk up to the door")
	await look_at_point(player, Vector3(0, 1.2, 0))
	check(player.aimed_interactable() == door, "door is under the crosshair")

	await look_at_point(player, Vector3(3, 1.2, 0))
	check(player.aimed_interactable() == null, "looking at the wall is not the door")

	await look_at_point(player, Vector3(0, 1.2, 0))
	player.input.crack = true
	await wait(0.4)
	player.input.crack = false
	check(door.state == Door.State.CRACKED, "crack key cracks the door once while held")
	player.input.interact = true
	await wait(0.6)
	player.input.interact = false
	check(door.state == Door.State.OPEN, "interact key opens it once while held")
	check_near(door.angle_deg, Cfg.door_open_angle_deg, 0.01, "door opened away from the player")


func test_locked_door_ignores_players_and_reset_closes_it() -> void:
	var player := _spawn(SOUTH)
	await look_at_point(player, Vector3(0, 1.2, 0))
	door.locked = true
	player.press_interact()
	player.press_crack()
	check(door.state == Door.State.CLOSED, "locked door stays closed")
	door.locked = false
	player.press_interact()
	await wait(0.6)
	check(door.state == Door.State.OPEN, "unlocked door opens")
	door.reset(true)
	check(door.state == Door.State.CLOSED and door.angle_deg == 0.0 and door.locked, "reset shuts and locks at once")
	await wait(0.02)
	check(not has_line_of_sight(Vector3(0, 1.5, 1.5), Vector3(0, 1.5, -1.5)), "reset door blocks sight by the next tick")
