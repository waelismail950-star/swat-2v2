extends TestCase
## Sound in a full offline world. a0, a1 are Entry; b0, b1 are Suspects.
## Audio output cannot be checked here; these tests check what would be played and how loud.

const EAR := Vector3(0, 1.4, 0)
const FOYER := Vector3(0, 0, 2.5)        # east of the Foyer-Living door
const LIVING := Vector3(-4.5, 0, 2.5)    # west of it, in line with the doorway

var world: World
var sounds: SoundSystem
var door: Door
var a0: Player
var b0: Player
var heard: Array[String] = []


func _ready() -> void:
	Cfg.setup_time = 0.5
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
	b0 = world.players["b0"]
	sounds = world.sounds
	door = world.house.doors["Foyer-Living"]
	sounds.emitted.connect(func(kind: String, _at: Vector3) -> void: heard.append(kind))
	world.game.start_match()


func _go_live() -> void:
	await wait(Cfg.setup_time + 0.1)
	heard.clear()


func _place(player: Player, at: Vector3, yaw := 0.0) -> void:
	player.respawn(Transform3D(Basis(Vector3.UP, yaw), at))
	await wait(0.1)
	heard.clear()


func _count(kind: String) -> int:
	return heard.count(kind)


func test_open_air_fades_with_distance_to_nothing_at_the_radius() -> void:
	var source := Vector3(-14, 1.4, 14)
	var radius: float = Cfg.noise_radius.step_walk
	var near := sounds.hearing("step_walk", source, source + Vector3(0, 0, 2))
	var mid := sounds.hearing("step_walk", source, source + Vector3(0, 0, radius * 0.5))
	var far := sounds.hearing("step_walk", source, source + Vector3(0, 0, radius + 1))
	check_near(near.loudness, 1.0 - 2.0 / radius, 0.001, "near")
	check_near(mid.loudness, 0.5, 0.001, "half the radius is half as loud")
	check_near(far.loudness, 0.0, 0.001, "silent beyond the radius")
	check(not near.muffled and near.from == source, "clear line of sight: heard as it is, from where it is")


func test_crouch_walking_is_far_quieter_than_walking_or_sprinting() -> void:
	var source := Vector3(-14, 1.4, 14)
	var ears := source + Vector3(0, 0, 6)
	check_near(sounds.hearing("step_crouch", source, ears).loudness, 0.0, 0.001, "crouch steps are inaudible at 6 m")
	var walk: float = sounds.hearing("step_walk", source, ears).loudness
	var sprint: float = sounds.hearing("step_sprint", source, ears).loudness
	check(walk > 0.2 and sprint > walk, "walking carries, sprinting carries further (%.2f, %.2f)" % [walk, sprint])


func test_a_closed_door_muffles_and_the_sound_comes_from_the_doorway() -> void:
	var source := FOYER + EAR
	var ears := LIVING + EAR
	var open_air: float = 1.0 - source.distance_to(ears) / Cfg.noise_radius.step_sprint

	var closed := sounds.hearing("step_sprint", source, ears)
	check_near(closed.loudness, open_air * Cfg.sound_closed_door_mult, 0.01, "closed door")
	check(closed.muffled, "it is muffled")
	check(closed.from.distance_to(door.side_point(0.0, 0.0, 1.4)) < 0.2, "and seems to come from the doorway (%s)" % closed.from)

	door.interact(Door.Action.TOGGLE_CRACK, FOYER)
	await wait(0.4)
	var cracked := sounds.hearing("step_sprint", source, ears)
	check_near(cracked.loudness, open_air * Cfg.sound_cracked_door_mult, 0.01, "cracked door lets more through")

	door.interact(Door.Action.TOGGLE_OPEN, FOYER)
	await wait(0.6)
	var open := sounds.hearing("step_sprint", source, ears)
	check_near(open.loudness, open_air, 0.01, "open door: as loud as open air")
	check(not open.muffled, "and clear")


func test_sound_bends_round_corners_through_open_doors() -> void:
	# Kitchen to Living with the door between them open, but no line of sight.
	world.house.doors["Living-Kitchen"].interact(Door.Action.TOGGLE_OPEN, Vector3(-4.5, 0, 2))
	await wait(0.6)
	var source := Vector3(-6.5, 1.4, -4.0)
	var ears := Vector3(-2.8, 1.4, 4.0)
	check(not has_line_of_sight(source, ears), "no line of sight")
	var result := sounds.hearing("step_walk", source, ears)
	check(result.loudness > 0.05, "still heard (%.2f)" % result.loudness)
	check(not result.muffled, "not muffled: nothing closed is in the way")
	check(result.from.distance_to(world.house.doors["Living-Kitchen"].side_point(0.0, 0.0, 1.4)) < 0.2, "heard from the doorway")
	var straight: float = 1.0 - source.distance_to(ears) / Cfg.noise_radius.step_walk
	check(result.loudness < straight, "the longer way round makes it quieter than a straight line would be")


func test_footsteps_overhead_come_through_the_floor() -> void:
	var source := Vector3(-4.5, House.UPPER_Y + 0.1, -2.5)   # walking in the Master bedroom
	var ears := Vector3(-4.5, 1.4, -2.5)                      # standing in the Kitchen below
	var result := sounds.hearing("step_walk", source, ears)
	var expected: float = (1.0 - source.distance_to(ears) / Cfg.noise_radius.step_walk) * Cfg.sound_wall_mult
	check_near(result.loudness, expected, 0.01, "heard through the floor")
	check(result.muffled and result.from == source, "muffled, from directly above")
	check_near(sounds.hearing("step_crouch", source, ears).loudness,
			(1.0 - source.distance_to(ears) / Cfg.noise_radius.step_crouch) * Cfg.sound_wall_mult, 0.01,
			"crouch steps overhead are fainter still")


func test_walking_makes_one_footstep_per_stride() -> void:
	await _place(a0, Vector3(-14, 0, 20))
	a0.input.move = Vector2(0, 1)
	await wait(3.0)
	a0.input.move = Vector2.ZERO
	var expected := Cfg.walk_speed * 3.0 / Cfg.stride_walk
	check(absf(_count("step_walk") - expected) <= 2.0, "about %.0f walking steps, got %d" % [expected, _count("step_walk")])
	check(_count("step_sprint") == 0 and _count("step_crouch") == 0, "all of them walking steps")
	heard.clear()
	await wait(1.0)
	check(heard.is_empty(), "standing still is silent: %s" % [heard])


func test_stance_and_speed_choose_the_footstep() -> void:
	await _place(a0, Vector3(-14, 0, 20))
	a0.input.move = Vector2(0, 1)
	a0.input.sprint = true
	await wait(0.5)
	heard.clear()
	await wait(1.5)
	check(_count("step_sprint") >= 5 and _count("step_walk") == 0, "sprinting: %s" % [heard])

	a0.input.sprint = false
	a0.input.crouch = true
	await wait(0.6)
	heard.clear()
	await wait(2.0)
	check(_count("step_crouch") >= 4 and _count("step_walk") == 0 and _count("step_sprint") == 0, "crouch-walking: %s" % [heard])


func test_respawning_is_not_a_footstep() -> void:
	await _place(a0, Vector3(-14, 0, 20))
	a0.respawn(Transform3D(Basis.IDENTITY, Vector3(14, 0, 20)))
	await wait(0.3)
	check(heard.is_empty(), "teleporting makes no step sound: %s" % [heard])


func test_doors_make_a_different_noise_for_open_crack_and_close() -> void:
	heard.clear()
	door.interact(Door.Action.TOGGLE_CRACK, FOYER)
	check(heard == ["door_crack"], "cracking: %s" % [heard])
	door.interact(Door.Action.TOGGLE_OPEN, FOYER)
	check(heard == ["door_crack", "door_open"], "opening: %s" % [heard])
	door.interact(Door.Action.TOGGLE_OPEN, FOYER)
	check(heard == ["door_crack", "door_open", "door_close"], "closing: %s" % [heard])
	check(Cfg.noise_radius.door_crack < Cfg.noise_radius.door_close and Cfg.noise_radius.door_close < Cfg.noise_radius.door_open,
			"cracking is the quietest, opening the loudest")


func test_each_weapon_has_its_own_shot_sound() -> void:
	await _go_live()
	await _place(a0, Vector3(-14, 0, 20))
	a0.input.fire = true
	await wait(0.05)
	a0.input.fire = false
	await wait(0.1)
	check(heard == ["shot_carbine"], "carbine: %s" % [heard])
	await _place(b0, Vector3(14, 0, 20))
	b0.input.fire = true
	await wait(0.05)
	b0.input.fire = false
	await wait(0.1)
	check(heard == ["shot_shotgun"], "shotgun, once per blast not per pellet: %s" % [heard])


func test_flashbang_is_heard_being_thrown_then_going_off() -> void:
	await _go_live()
	await _place(a0, Vector3(-14, 0, 20))
	a0.input.gadget_1 = true
	await wait(0.05)
	a0.input.gadget_1 = false
	await wait(0.2)
	check(heard == ["throw"], "the throw: %s" % [heard])
	await wait(Cfg.flash_fuse)
	check(heard == ["throw", "bang"], "then the bang: %s" % [heard])


func test_breaching_charge_beeps_until_it_blows() -> void:
	await _go_live()
	door.place_charge(1.0)
	await wait(Cfg.breach_fuse + 0.3)
	var expected := Cfg.breach_fuse / Cfg.fuse_beep_interval
	check(absf(_count("fuse") - expected) <= 1.5, "about %.0f beeps, got %d" % [expected, _count("fuse")])
	check(_count("bang") == 1, "one bang")
	check(_count("door_open") == 0, "no creak: the door was blown, not opened")
	heard.clear()
	await wait(1.0)
	check(_count("fuse") == 0, "beeping stops")


func test_forcing_a_wedged_door_thumps_while_it_is_held() -> void:
	await _go_live()
	door.set_wedged(true)
	await _place(a0, Vector3(-0.7, 0, 2.5), PI / 2)
	a0.input.interact = true
	await wait(2.0)
	check(door.forcing, "door reports it is being forced")
	var expected := 2.0 / Cfg.force_thump_interval
	check(absf(_count("force") - expected) <= 1.5, "about %.0f thumps in 2 s, got %d" % [expected, _count("force")])
	a0.input.interact = false
	await wait(0.2)
	heard.clear()
	await wait(1.0)
	check(not door.forcing and _count("force") == 0, "silent once the player lets go")


func test_trip_alarm_sounds_for_everyone() -> void:
	await _go_live()
	door.place_alarm(door.side_of(LIVING))
	a0.respawn(Transform3D(Basis.IDENTITY, Vector3(-3.0, 0, 2.5)))   # just inside the doorway
	await wait(0.4)
	check(_count("alarm") == 1, "alarm sounded: %s" % [heard])
	check(Cfg.noise_radius.alarm >= 20.0, "and it is loud enough to carry through the house")


func test_sound_bank_has_a_clear_and_a_muffled_version_of_every_sound() -> void:
	var bank := SoundBank.build()
	for kind: String in Cfg.noise_radius:
		check(bank.has(kind), "%s has audio" % kind)
		if bank.has(kind):
			check(bank[kind].size() == 2 and bank[kind][0].data.size() > 500 and bank[kind][1].data.size() == bank[kind][0].data.size(),
					"%s has a clear and a muffled version" % kind)
	check(bank.size() == Cfg.noise_radius.size(), "no sound without a radius, no radius without a sound")
