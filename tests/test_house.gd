extends TestCase
## Walks real routes through the real house, so broken stairs, doorways or floor seams fail here.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var house: House


func _ready() -> void:
	house = House.new()
	add_child(house)


func _spawn(at: Vector3) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	player.position = at
	add_child(player)
	return player


func _open(door_name: String, player: Player) -> void:
	house.doors[door_name].interact(Door.Action.TOGGLE_OPEN, player.global_position)
	await wait(0.6)


## Walks the points in order; reports the first leg that fails.
func _walk_route(player: Player, points: Array[Vector3], label: String) -> void:
	for i in points.size():
		if not await walk_to(player, points[i]):
			check(false, "%s: stuck on leg %d toward %s at %s" % [label, i, points[i], player.global_position])
			return


func test_has_all_doors_closed_at_start() -> void:
	check(house.doors.size() == House.DOORS.size(), "every door spec builds a door")
	for door: Door in house.doors.values():
		check(door.state == Door.State.CLOSED, "%s starts closed" % door.door_name)


func test_no_view_inside_from_outside_with_doors_closed() -> void:
	var outside: Array[Vector3] = [Vector3(0, 1.6, 9), Vector3(6, 1.6, 9), Vector3(-6, 1.6, 9),
			Vector3(7.9, 1.6, 8), Vector3(5, 4.6, 3), Vector3(12, 1.6, 0)]
	for room: Dictionary in House.ROOMS:
		if room.name == "Deck":
			continue
		var c: Vector2 = room.rect.get_center()
		var inside := Vector3(c.x, room.y + 1.5, c.y)
		for eye in outside:
			check(not has_line_of_sight(eye, inside), "can see %s from %s" % [room.name, eye])


func test_front_door_to_upper_hall_by_the_stairs() -> void:
	var player := _spawn(Vector3(0, 0.05, 8))
	await wait(0.2)
	check(not await walk_to(player, Vector3(0, 0, 3), 3.0), "closed front door keeps the player out")
	await _open("Front Door", player)
	await _walk_route(player, [Vector3(0, 0, 3), Vector3(1, 0, -1), Vector3(1, 0, -4.3),
			Vector3(-1, 0, -4.3), Vector3(-1, 0, -0.8), Vector3(0, 0, 1)], "stairs up")
	check_near(player.global_position.y, House.UPPER_Y, 0.05, "should be standing on the upper floor")
	check(player.is_on_floor(), "should be grounded upstairs")
	# And back down.
	await _walk_route(player, [Vector3(-1, 0, -0.8), Vector3(-1, 0, -4.3), Vector3(1, 0, -4.3),
			Vector3(1, 0, -1), Vector3(0, 0, 2)], "stairs down")
	check_near(player.global_position.y, 0.0, 0.05, "should be back on the ground floor")


func test_exterior_ramp_to_deck_door_to_upper_hall() -> void:
	var player := _spawn(Vector3(7.9, 0.05, 9))
	await wait(0.2)
	await _walk_route(player, [Vector3(7.9, 0, 0.8), Vector3(3.2, 0, 2.5)], "ramp to deck")
	check_near(player.global_position.y, House.UPPER_Y, 0.05, "should be on the deck")
	await _open("Deck Door", player)
	await _walk_route(player, [Vector3(0, 0, 2.5)], "deck door")
	check_near(player.global_position.y, House.UPPER_Y, 0.05, "should be in the upper hall")


func test_ground_floor_west_loop() -> void:
	var player := _spawn(Vector3(0, 0.05, 3))
	await wait(0.2)
	await _walk_route(player, [Vector3(-1.0, 0, 2.5)], "to living door")
	await _open("Foyer-Living", player)
	await _walk_route(player, [Vector3(-4.5, 0, 2.5), Vector3(-4.5, 0, 1.0)], "through living")
	await _open("Living-Kitchen", player)
	await _walk_route(player, [Vector3(-4.5, 0, -2), Vector3(-3.2, 0, -0.75)], "through kitchen")
	await _open("Kitchen-Foyer", player)
	await _walk_route(player, [Vector3(0, 0, -0.75), Vector3(0, 0, 3)], "back to foyer")


func test_ground_floor_east_loop() -> void:
	var player := _spawn(Vector3(0, 0.05, 3))
	await wait(0.2)
	await _walk_route(player, [Vector3(1.0, 0, 2.5)], "to study door")
	await _open("Study-Foyer", player)
	await _walk_route(player, [Vector3(4.5, 0, 2.5), Vector3(4.5, 0, 1.0)], "through study")
	await _open("Dining-Study", player)
	await _walk_route(player, [Vector3(4.5, 0, -2), Vector3(3.2, 0, -0.75)], "through dining")
	await _open("Dining-Foyer", player)
	await _walk_route(player, [Vector3(0.6, 0, -0.75), Vector3(0, 0, 3)], "back to foyer")


func test_upper_floor_loop_and_kids_room() -> void:
	var player := _spawn(Vector3(0, House.UPPER_Y + 0.05, 2.5))
	await wait(0.2)
	await _walk_route(player, [Vector3(-1.0, 0, 2.5)], "to bedroom door")
	await _open("Hall-Bedroom", player)
	await _walk_route(player, [Vector3(-4.5, 0, 2.5), Vector3(-4.5, 0, 1.0)], "through bedroom")
	await _open("Master-Bedroom", player)
	await _walk_route(player, [Vector3(-4.5, 0, -2), Vector3(-3.2, 0, -0.75)], "through master")
	await _open("Hall-Master", player)
	await _walk_route(player, [Vector3(-0.5, 0, -0.75), Vector3(1.0, 0, -0.75)], "across the hall")
	await _open("Hall-Kids", player)
	await _walk_route(player, [Vector3(3.2, 0, -0.75), Vector3(4.5, 0, -2.5)], "into kids room")
	check_near(player.global_position.y, House.UPPER_Y, 0.05, "still on the upper floor")


func test_every_door_opens_fully_both_ways() -> void:
	for door: Door in house.doors.values():
		for side: float in [1.0, -1.0]:
			var operator := door.to_global(Vector3(0.5, 0, side * 1.5))
			door.interact(Door.Action.TOGGLE_OPEN, operator)
			await wait(0.5)
			check_near(door.angle_deg, side * Cfg.door_open_angle_deg, 0.01,
					"%s should open away from side %+d" % [door.door_name, side])
			door.interact(Door.Action.TOGGLE_OPEN, operator)
			await wait(0.5)
			check_near(door.angle_deg, 0.0, 0.01, "%s should close" % door.door_name)
