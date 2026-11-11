extends TestCase
## A full offline world with four code-driven players: a0, a1 are Entry, b0, b1 are Suspects.
## Most tests use the Foyer-Living door: the Foyer is its east side, the Living room its west.

const DOOR := "Foyer-Living"
const FOYER_SIDE := Vector3(-0.7, 0, 2.5)    # standing in the Foyer, at the door
const LIVING_SIDE := Vector3(-3.3, 0, 2.5)   # standing in the Living room, at the door
const FACE_WEST := PI / 2
const FACE_EAST := -PI / 2

var world: World
var door: Door
var a0: Player
var a1: Player
var b0: Player
var b1: Player
var alarms: Array[String] = []


func _ready() -> void:
	Cfg.setup_time = 1.0
	Cfg.round_time = 300.0
	world = World.new()
	add_child(world)
	var participants := []
	for id: String in ["a0", "a1", "b0", "b1"]:
		participants.append({id = id, label = id, peer = 1, roster = 0 if id.begins_with("a") else 1, bot = false})
	world.build(participants)
	for player: Player in world.players.values():
		player.controlled_locally = false
	a0 = world.players["a0"]
	a1 = world.players["a1"]
	b0 = world.players["b0"]
	b1 = world.players["b1"]
	door = world.house.doors[DOOR]
	world.gadgets.alarm_raised.connect(func(d: Door) -> void: alarms.append(d.door_name))
	world.game.start_match()


func _go_live() -> void:
	await wait(Cfg.setup_time + 0.1)


func _place(player: Player, at: Vector3, yaw: float) -> void:
	player.respawn(Transform3D(Basis(Vector3.UP, yaw), at))
	await wait(0.1)


## Everyone not needed for a test waits far out on the lawn.
func _park(players: Array[Player]) -> void:
	for i in players.size():
		players[i].respawn(Transform3D(Basis.IDENTITY, Vector3(-20 + i * 2, 0, 22)))
	await wait(0.1)


func _tap(player: Player, slot: int) -> void:
	if slot == 0:
		player.input.gadget_1 = true
	else:
		player.input.gadget_2 = true
	await wait(0.05)
	player.input.gadget_1 = false
	player.input.gadget_2 = false
	await wait(0.05)


func _cycle_loadout(player: Player) -> void:
	player.input.next_loadout = true
	await wait(0.05)
	player.input.next_loadout = false
	await wait(0.05)


func test_each_side_starts_with_its_gadgets_and_charges() -> void:
	check(a0.gadgets == ["flashbang", "door_camera"], "entry default kit: %s" % [a0.gadgets])
	check(a0.gadget_charges == [Cfg.gadget_charges.flashbang, -1], "entry charges: %s" % [a0.gadget_charges])
	check(b0.gadgets == ["wedge", "alarm"], "suspect kit: %s" % [b0.gadgets])
	check(b0.gadget_charges == [Cfg.gadget_charges.wedge, Cfg.gadget_charges.alarm], "suspect charges")


func test_entry_picks_two_of_three_during_setup_only() -> void:
	await _cycle_loadout(a0)
	check(a0.gadgets == ["flashbang", "breach"], "second pair: %s" % [a0.gadgets])
	await _cycle_loadout(a0)
	check(a0.gadgets == ["door_camera", "breach"], "third pair: %s" % [a0.gadgets])
	await _cycle_loadout(a0)
	check(a0.gadgets == ["flashbang", "door_camera"], "wraps around")
	await _cycle_loadout(a0)
	await _go_live()
	await _cycle_loadout(a0)
	check(a0.gadgets == ["flashbang", "breach"], "no changing once the round is live: %s" % [a0.gadgets])
	check(a1.gadgets == ["flashbang", "door_camera"], "teammates choose separately")


func _grenade() -> Flashbang:
	for node in world.get_children():
		if node is Flashbang:
			return node
	return null


func _face(player: Player, point: Vector3, away: bool) -> void:
	var to := point - player.global_position
	player.input.yaw = atan2(-to.x, -to.z) + (PI if away else 0.0)


func test_flashbang_blinds_by_distance_and_facing_and_spares_the_hostage() -> void:
	await _go_live()
	await _place(a0, Vector3(-12, 0, 20), 0.0)           # thrower, facing north
	await _place(b0, Vector3(-13.5, 0, 9.5), 0.0)        # will look at the grenade
	await _place(b1, Vector3(-10.5, 0, 9.5), 0.0)        # same distance, will look away
	await _place(a1, Vector3(-12, 0, -12), 0.0)          # far side of the house
	var bangs: Array[Vector3] = []
	world.gadgets.banged.connect(func(at: Vector3) -> void: bangs.append(at))

	await _tap(a0, 0)
	check(a0.gadget_charges[0] == Cfg.gadget_charges.flashbang - 1, "one charge used")
	await wait(Cfg.flash_fuse - 0.3)
	check_near(b0.flash_left, 0.0, 0.001, "nothing before the fuse runs out")
	var grenade := _grenade()
	check(grenade != null and grenade.global_position.z < 16.0, "the grenade has travelled")
	_face(b0, grenade.global_position, false)
	_face(b1, grenade.global_position, true)
	await wait(0.5)

	check(bangs.size() == 1, "one bang")
	check(_grenade() == null or _grenade().is_queued_for_deletion(), "the grenade is gone")
	check(b0.flash_left > 1.5, "looking at it up close: blind (%.2f s)" % b0.flash_left)
	check(b1.flash_left > 0.0 and b1.flash_left < b0.flash_left * 0.6, "back turned: much less (%.2f s)" % b1.flash_left)
	check(a0.flash_left < b0.flash_left, "the thrower, further away, gets less (%.2f s)" % a0.flash_left)
	check_near(a1.flash_left, 0.0, 0.001, "no line of sight: nothing")
	check(world.hostage.state == Hostage.State.HELD, "the hostage is unharmed")
	await wait(Cfg.flash_duration + 0.5)
	check_near(b0.flash_left, 0.0, 0.001, "blindness wears off")


func test_flash_strength_rules() -> void:
	await _park([a0, a1, b1])
	await _place(b0, Vector3(-12, 0, 12), 0.0)   # facing north
	var eyes := b0.head.global_position
	var gadgets := world.gadgets
	var near := gadgets.flash_seconds(b0, eyes + Vector3(0, 0, -1), 9.0, 3.5)
	var far := gadgets.flash_seconds(b0, eyes + Vector3(0, 0, -8), 9.0, 3.5)
	var behind := gadgets.flash_seconds(b0, eyes + Vector3(0, 0, 1), 9.0, 3.5)
	check(near > far and far > 0.0, "weaker with distance (%.2f vs %.2f)" % [near, far])
	check_near(behind, near * Cfg.flash_look_away_mult, 0.01, "facing away multiplies it down")
	check_near(gadgets.flash_seconds(b0, eyes + Vector3(0, 0, -9.5), 9.0, 3.5), 0.0, 0.001, "nothing beyond the radius")
	Greybox.add_box(world, Vector3(-12, 1.5, 10), Vector3(4, 3, 0.2), Color.WHITE)
	await wait(0.05)
	check_near(gadgets.flash_seconds(b0, eyes + Vector3(0, 0, -4), 9.0, 3.5), 0.0, 0.001, "nothing through a wall")
	b0.take_hit(1000.0, Hitbox.Zone.BODY, null)
	check_near(gadgets.flash_seconds(b0, eyes + Vector3(0, 0, 1), 9.0, 3.5), 0.0, 0.001, "nothing for a downed player")


func test_flashbangs_run_out() -> void:
	await _go_live()
	await _place(a0, Vector3(-12, 0, 18), 0.0)
	for i in Cfg.gadget_charges.flashbang + 1:
		await _tap(a0, 0)
		await wait(0.3)
	check(a0.gadget_charges[0] == 0, "all charges used")
	await wait(0.2)
	var in_flight := world.get_children().filter(func(n: Node) -> bool: return n is Flashbang).size()
	check(in_flight == Cfg.gadget_charges.flashbang, "only %d grenades were ever thrown, saw %d" % [Cfg.gadget_charges.flashbang, in_flight])


func test_no_flashbangs_during_setup() -> void:
	await _place(a0, Vector3(-12, 0, 18), 0.0)
	await _tap(a0, 0)
	check(a0.gadget_charges[0] == Cfg.gadget_charges.flashbang, "nothing thrown, nothing spent")


func test_closed_door_blocks_a_flash_and_it_blinds_the_thrower() -> void:
	await _go_live()
	await _park([a1, b1])
	await _place(a0, FOYER_SIDE + Vector3(1.5, 0, 0), FACE_WEST)   # 1.5 m back from the shut door
	await _place(b0, LIVING_SIDE + Vector3(-1.0, 0, 0), FACE_EAST)  # just behind it
	await _tap(a0, 0)
	await wait(Cfg.flash_fuse + 0.2)
	check_near(b0.flash_left, 0.0, 0.001, "the door protects the room")
	check(a0.flash_left > 1.0, "it bounced back and blinded the thrower (%.2f s)" % a0.flash_left)


func test_flashbang_through_an_open_door_blinds_the_room() -> void:
	await _go_live()
	await _park([a1, b1])
	await _place(a0, FOYER_SIDE + Vector3(1.5, 0, 0), FACE_WEST)
	await _place(b0, Vector3(-5.5, 0, 2.5), FACE_EAST)
	door.interact(Door.Action.TOGGLE_OPEN, a0.global_position)
	await wait(0.6)
	await _tap(a0, 0)
	await wait(Cfg.flash_fuse - 0.3)
	var grenade := _grenade()
	if grenade != null:
		_face(b0, grenade.global_position, false)   # a careless defender who watches it land
	await wait(0.5)
	check(b0.flash_left > 0.5, "with the door open the flash reaches the defender (%.2f s)" % b0.flash_left)


func test_blind_bot_sees_nobody_but_fires_the_way_it_was_facing() -> void:
	Cfg.round_end_time = 100.0
	Cfg.weapons.shotgun.spread_deg = 0.0
	await _go_live()
	await _place(b0, Vector3(-12, 0, 14), 0.0)     # facing north
	await _place(a0, Vector3(-8, 0, 8), PI)        # off to the side, in plain view of nobody once blind
	await _park([a1, b1])
	world.give_brain(b0)
	check(b0.brain._visible_enemy() == null or b0.brain._visible_enemy() == a0, "setup sanity")
	b0.apply_flash(3.0)
	check(b0.brain._visible_enemy() == null, "blinded, it sees nobody")
	await wait(2.0)
	check_near(a0.health, Cfg.max_health, 0.01, "so someone off its line of fire is untouched")
	check(b0.arsenal.weapon().ammo < Cfg.weapons.shotgun.mag, "but it is firing blind, at the way it was facing")


func test_blind_guards_punish_walking_through_the_line_they_were_holding() -> void:
	Cfg.round_end_time = 100.0
	Cfg.weapons.shotgun.spread_deg = 1.0
	await _go_live()
	await _place(b0, Vector3(-12, 0, 14), 0.0)     # facing north
	await _place(a0, Vector3(-12, 0, 9), PI)       # standing right in the line it is aimed down
	await _park([a1, b1])
	world.give_brain(b0)
	b0.apply_flash(3.0)
	await wait(2.5)
	check(a0.is_dead, "entering while the guard is blind but still aimed at the door is still fatal (health %.0f)" % a0.health)


func test_wedge_holds_a_door_until_forced() -> void:
	await _park([a1, b1])
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 0)   # wedging is allowed during setup
	check(door.wedged, "door is wedged")
	check(b0.gadget_charges[0] == Cfg.gadget_charges.wedge - 1, "one wedge used")
	await _tap(b0, 0)
	check(b0.gadget_charges[0] == Cfg.gadget_charges.wedge - 1, "a second wedge on the same door is not spent")

	await _go_live()
	await _place(a0, FOYER_SIDE, FACE_WEST)
	a0.press_interact()
	a0.press_crack()
	await wait(0.3)
	check(door.state == Door.State.CLOSED, "a wedged door does not open or crack")

	a0.input.interact = true
	await wait(Cfg.wedge_force_time * 0.5)
	a0.input.interact = false
	await wait(0.2)
	a0.input.interact = true
	await wait(Cfg.wedge_force_time * 0.7)
	check(door.wedged, "letting go loses the progress")
	await wait(Cfg.wedge_force_time * 0.4)
	a0.input.interact = false
	check(not door.wedged, "an uninterrupted hold forces it")
	check(door.state == Door.State.CLOSED, "forcing breaks the wedge but leaves the door shut")
	a0.press_interact()
	await wait(0.6)
	check(door.state == Door.State.OPEN, "now it opens normally")


func test_suspect_removes_own_wedge_and_cannot_wedge_an_open_door() -> void:
	await _park([a0, a1, b1])
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 0)
	check(door.wedged, "wedged")
	b0.press_interact()
	check(not door.wedged and door.state == Door.State.CLOSED, "a suspect's interact pulls the wedge out")
	b0.press_interact()
	await wait(0.6)
	check(door.state == Door.State.OPEN, "then the door works normally")
	await look_at_point(b0, door.panel_point())
	await _tap(b0, 0)
	check(not door.wedged and b0.gadget_charges[0] == Cfg.gadget_charges.wedge - 1, "an open door cannot be wedged")


func test_breaching_charge_blows_a_wedged_door_and_stuns_those_close() -> void:
	await _cycle_loadout(a0)   # flashbang + breach
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 0)
	check(door.wedged, "door is wedged")
	await _go_live()
	await _place(b0, LIVING_SIDE + Vector3(-1.0, 0, 0), FACE_EAST)   # 2.3 m inside, facing the door
	await _place(b1, Vector3(-5.5, 0, 0.8), 0.0)                      # in the room but round the corner of the blast
	await _place(a0, FOYER_SIDE, FACE_WEST)
	await _place(a1, Vector3(0, 0, -1.2), 0.0)                        # in the Foyer, well back

	await _tap(a0, 1)
	check(door.charge_side != 0.0 and a0.gadget_charges[1] == 0, "charge placed and spent")
	a0.press_interact()
	await wait(0.2)
	check(door.state == Door.State.CLOSED, "the door cannot be opened while the charge is on it")
	await wait(Cfg.breach_fuse * 0.5)
	check(door.state == Door.State.CLOSED and door.wedged, "nothing until the fuse runs out")
	await wait(Cfg.breach_fuse * 0.5 + 0.2)
	check(door.state == Door.State.OPEN and not door.wedged and door.charge_side == 0.0, "door is blown open, wedge gone")
	check(b0.flash_left > 0.8, "defender close behind the door is stunned (%.2f s)" % b0.flash_left)
	check(a0.flash_left > 0.8, "so is the operator who stayed next to it (%.2f s)" % a0.flash_left)
	check_near(a1.flash_left, 0.0, 0.001, "the operator who stood back is fine")
	check_near(b1.flash_left, 0.0, 0.001, "a defender beyond the blast radius is fine")
	check(world.hostage.state == Hostage.State.HELD, "no damage to the hostage")
	await wait(0.5)
	check(absf(door.angle_deg) > 80.0, "door swung fully open")


func test_trip_alarm_warns_once_when_entry_passes() -> void:
	await _park([a1])
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 1)
	check(door.alarm_side == door.side_of(LIVING_SIDE), "alarm sits on the side it was placed from")
	check(b0.gadget_charges[1] == Cfg.gadget_charges.alarm - 1, "one alarm used")
	await _go_live()
	# A suspect walking over it does nothing.
	await _place(b1, LIVING_SIDE + Vector3(-0.3, 0, 0.3), 0.0)
	await wait(0.3)
	check(alarms.is_empty() and door.alarm_side != 0.0, "suspects do not set it off")
	await _park([b0, b1])

	await _place(a0, FOYER_SIDE, FACE_WEST)
	await wait(0.3)
	check(alarms.is_empty(), "standing outside the shut door is not close enough to matter")
	a0.press_interact()
	await wait(0.6)
	check(await walk_to(a0, LIVING_SIDE + Vector3(-1.5, 0, 0), 4.0), "operator walks in")
	check(alarms == [DOOR], "alarm raised once, naming the door: %s" % [alarms])
	check(door.alarm_side == 0.0, "the alarm is spent")


func test_trip_alarm_can_be_shot() -> void:
	Cfg.weapons.carbine.spread_deg = 0.0
	await _park([a1, b1])
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 1)
	await _go_live()
	await _park([b0])
	# Operator already inside the room by another route, three metres from the alarm.
	await _place(a0, Vector3(-5.5, 0, 4.2), 0.0)
	await look_at_point(a0, door.side_point(door.alarm_side, Door.ALARM_INSET, 0.06))
	a0.input.fire = true
	await wait(0.05)
	a0.input.fire = false
	await wait(0.1)
	check(door.alarm_side == 0.0, "one bullet destroys the alarm")
	check(await walk_to(a0, LIVING_SIDE, 4.0), "operator walks over where it was")
	check(alarms.is_empty(), "no alert was raised")


func test_door_camera_sees_the_room_without_opening_the_door() -> void:
	await _go_live()
	await _park([a1, b1])
	await _place(a0, FOYER_SIDE, FACE_WEST)
	await _place(b0, Vector3(-5.0, 0, 3.5), FACE_EAST)
	var hidden := b0.head.global_position
	check(not has_line_of_sight(a0.camera.global_position, hidden), "the operator cannot see the defender through the door")

	a0.input.gadget_2 = true
	await wait(0.2)
	check(a0.peek_door == door, "door camera is in use")
	var lens := a0.active_camera()
	check(lens != a0.camera and world.house.region_at(lens.global_position) == "Living", "the view is inside the room")
	check(lens.global_position.y < 0.2, "at floor level")
	check(has_line_of_sight(lens.global_position, hidden), "the defender is visible from there")
	check(lens.is_position_in_frustum(hidden), "and in frame")
	check(door.scope_side == door.side_of(LIVING_SIDE), "the lens is visible on the room side of the door")
	check(door.state == Door.State.CLOSED, "the door stays shut")

	# The user is rooted and cannot shoot.
	var stood := a0.global_position
	a0.input.move = Vector2(0, -1)
	a0.input.fire = true
	await wait(0.5)
	a0.input.move = Vector2.ZERO
	a0.input.fire = false
	check(a0.global_position.distance_to(stood) < 0.05, "cannot walk while looking")
	check(a0.arsenal.weapon().ammo == Cfg.weapons.carbine.mag, "cannot shoot while looking")

	# The mouse pans the lens within limits, not the body.
	a0.input.yaw += deg_to_rad(170.0)
	await wait(0.1)
	check_near(rad_to_deg(angle_difference(FACE_WEST, a0.input.yaw)), Cfg.door_camera_pan_deg, 0.5, "pan is limited")
	check_near(a0.rotation.y, FACE_WEST, 0.01, "the body does not turn")

	a0.input.gadget_2 = false
	await wait(0.1)
	check(a0.peek_door == null and a0.active_camera() == a0.camera, "releasing the key puts it away")
	check_near(a0.input.yaw, FACE_WEST, 0.01, "and the view returns to where it was")
	check(door.scope_side == 0.0, "the lens is gone")


func test_door_camera_ends_when_the_door_opens_or_the_user_goes_down() -> void:
	await _go_live()
	await _park([a1, b0, b1])
	await _place(a0, FOYER_SIDE, FACE_WEST)
	a0.input.gadget_2 = true
	await wait(0.2)
	check(a0.peek_door == door, "looking")
	door.interact(Door.Action.TOGGLE_CRACK, LIVING_SIDE)
	await wait(0.2)
	check(a0.peek_door == null and door.scope_side == 0.0, "someone cracking the door ends it")

	door.interact(Door.Action.TOGGLE_CRACK, LIVING_SIDE)
	a0.input.gadget_2 = false
	await wait(0.4)
	a0.input.gadget_2 = true
	await wait(0.2)
	check(a0.peek_door == door, "looking again")
	a0.take_hit(1000.0, Hitbox.Zone.BODY, null)
	check(a0.peek_door == null and door.scope_side == 0.0, "going down ends it")


func test_new_round_clears_gadgets_and_refills_charges() -> void:
	Cfg.round_end_time = 0.3
	await _place(b0, LIVING_SIDE, FACE_EAST)
	await _tap(b0, 0)
	await _tap(b0, 1)
	await _go_live()
	await _place(a0, Vector3(-12, 0, 18), 0.0)
	await _tap(a0, 0)
	check(door.wedged and door.alarm_side != 0.0, "gadgets are out")
	a0.take_hit(1000.0, Hitbox.Zone.BODY, b0)
	a1.take_hit(1000.0, Hitbox.Zone.BODY, b0)
	await wait(Cfg.round_end_time + 0.3)
	check(world.game.board.round_number == 2, "round 2")
	check(not door.wedged and door.alarm_side == 0.0, "doors are clean")
	check(a0.gadget_charges[0] == Cfg.gadget_charges.flashbang and b0.gadget_charges == [Cfg.gadget_charges.wedge, Cfg.gadget_charges.alarm], "charges are back")
	var grenades := world.get_children().filter(func(n: Node) -> bool: return n is Flashbang and not n.is_queued_for_deletion()).size()
	check(grenades == 0, "no grenade survives into the next round")
