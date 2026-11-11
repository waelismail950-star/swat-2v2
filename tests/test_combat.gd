extends TestCase
## Shooter stands at the origin facing -Z. Targets stand 5 m down range, facing the same way,
## so a target's right-hand side is +X.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RANGE := Vector3(0, 0, -5)
const HEAD_Y := 1.68   # standing head centre: stand_height - eye_drop
const CHEST_Y := 1.2

var shooter: Player
var shots_fired := 0


func _ready() -> void:
	Greybox.add_box(self, Vector3(0, -0.25, 0), Vector3(60, 0.5, 60), Color.GRAY)
	# Perfectly accurate weapons unless a test says otherwise.
	for id: String in Cfg.weapons:
		Cfg.weapons[id].spread_deg = 0.0
		Cfg.weapons[id].move_spread_deg = 0.0
	shooter = _spawn(Vector3.ZERO, ["carbine", "pistol", "shotgun"])
	shooter.arsenal.rng.seed = 7
	shooter.arsenal.fired.connect(func(_w: Weapon, _f: Vector3, _s: Array) -> void: shots_fired += 1)


## Targets are Suspects (no armor) unless a test changes their team.
func _spawn(at: Vector3, weapons: Array[String] = ["pistol"]) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.controlled_locally = false
	player.position = at
	add_child(player)
	player.team = Team.Id.SUSPECTS
	player.arsenal.equip(weapons)
	return player


## One trigger pull and release.
func _pull_trigger() -> void:
	shooter.input.fire = true
	await wait(0.02)
	shooter.input.fire = false
	await wait(0.02)


func _select(slot: int) -> void:
	shooter.input.weapon_slot = slot
	await wait(Cfg.weapon_swap_time + 0.05)


func test_body_shot_does_weapon_damage() -> void:
	var target := _spawn(RANGE)
	await look_at_point(shooter, RANGE + Vector3(0, CHEST_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health - Cfg.weapons.carbine.damage, 0.01, "one carbine body hit")
	check(not target.is_dead, "target survives one body hit")


func test_legs_count_as_body() -> void:
	var target := _spawn(RANGE)
	await look_at_point(shooter, RANGE + Vector3(0, 0.4, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health - Cfg.weapons.carbine.damage, 0.01, "leg hit is a body hit")


func test_entry_armor_reduces_body_damage_but_not_headshots() -> void:
	var armored := _spawn(RANGE)
	armored.team = Team.Id.ENTRY
	await look_at_point(shooter, RANGE + Vector3(0, CHEST_Y, 0))
	await _pull_trigger()
	check_near(armored.health, Cfg.max_health - Cfg.weapons.carbine.damage * Cfg.entry_body_damage_mult, 0.01,
			"armor scales body damage")
	await wait(1.0)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check(armored.is_dead, "armor does not save you from a headshot")


func test_suspects_are_slower() -> void:
	var suspect := _spawn(Vector3(10, 0, 0))
	suspect.input.move = Vector2(0, 1)
	await wait(1.0)
	check_near(Vector2(suspect.velocity.x, suspect.velocity.z).length(),
			Cfg.walk_speed * Cfg.suspect_speed_mult, 0.05, "suspect walk speed")


func test_safe_weapons_cannot_fire() -> void:
	shooter.arsenal.safe = true
	await _pull_trigger()
	check(shots_fired == 0, "no shots while safe")
	shooter.arsenal.safe = false
	await _pull_trigger()
	check(shots_fired == 1, "fires once live")


func test_any_head_hit_is_lethal_even_one_weak_pellet() -> void:
	Cfg.weapons.shotgun.pellets = 1
	Cfg.weapons.shotgun.damage = 1.0
	var target := _spawn(RANGE)
	await _select(2)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check(target.is_dead, "one pellet doing 1 damage to the head kills (health %.0f)" % target.health)


func test_headshot_is_lethal_at_any_range_and_through_armor() -> void:
	Cfg.weapons.carbine.falloff_min = 0.1
	var far := _spawn(Vector3(0, 0, -45))
	far.team = Team.Id.ENTRY
	await look_at_point(shooter, Vector3(0, HEAD_Y, -45))
	await _pull_trigger()
	check(far.is_dead, "armored target at 45 m, where damage has fallen off, still dies to the head (health %.0f)" % far.health)


func test_headshot_lethality_can_be_turned_off_in_the_config() -> void:
	Cfg.headshot_lethal = false
	Cfg.headshot_mult = 2.0
	var target := _spawn(RANGE)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health - Cfg.weapons.carbine.damage * 2.0, 0.01, "the multiplier applies instead")
	check(not target.is_dead, "and one head hit no longer kills")


func test_headshot_kills_and_reports_killer() -> void:
	var target := _spawn(RANGE)
	var report := {}
	target.died.connect(func(victim: Player, killer: Node) -> void:
		report.victim = victim
		report.killer = killer)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check(target.is_dead, "headshot should be lethal")
	check(report.get("victim") == target and report.get("killer") == shooter, "died signal names victim and killer")


func test_wall_stops_bullets() -> void:
	var target := _spawn(RANGE)
	Greybox.add_box(self, Vector3(0, 1.5, -2.5), Vector3(4, 3, 0.2), Color.WHITE)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health, 0.01, "wall should stop the bullet")


func test_door_stops_bullets_until_opened() -> void:
	var target := _spawn(RANGE)
	var door := Door.new()
	door.position = Vector3(-0.5, 0, -2.5)
	add_child(door)
	await look_at_point(shooter, RANGE + Vector3(0, CHEST_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health, 0.01, "closed door stops the bullet")
	door.interact(Door.Action.TOGGLE_OPEN, shooter.global_position)
	await wait(0.6)
	await _pull_trigger()
	check(target.health < Cfg.max_health, "open door lets the bullet through")


func test_auto_weapon_fires_at_its_rate_while_held() -> void:
	shooter.input.fire = true
	await wait(1.0)
	shooter.input.fire = false
	var expected: float = 1.0 / Cfg.weapons.carbine.fire_interval
	check(absf(shots_fired - expected) <= 1.0, "about %.1f shots in 1 s, got %d" % [expected, shots_fired])
	check(shooter.arsenal.weapon().ammo == Cfg.weapons.carbine.mag - shots_fired, "each shot uses one round")


func test_semi_auto_fires_once_per_pull() -> void:
	await _select(1)
	shooter.input.fire = true
	await wait(1.0)
	shooter.input.fire = false
	check(shots_fired == 1, "holding the trigger fires once, got %d" % shots_fired)
	await wait(0.2)
	await _pull_trigger()
	check(shots_fired == 2, "second pull fires again, got %d" % shots_fired)


func test_empty_magazine_reloads_and_cannot_fire_meanwhile() -> void:
	var gun := shooter.arsenal.weapon()
	gun.ammo = 1
	await _pull_trigger()
	check(gun.ammo == 0 and shots_fired == 1, "last round fired")
	shooter.input.fire = true
	await wait(Cfg.weapons.carbine.reload_time - 0.2)
	check(gun.is_reloading(), "pulling the trigger on empty starts a reload")
	check(shots_fired == 1, "no shots while reloading")
	await wait(0.4)
	shooter.input.fire = false
	check(gun.ammo > 0 and shots_fired > 1, "reload finished and firing resumed")


func test_manual_reload_refills_magazine() -> void:
	var gun := shooter.arsenal.weapon()
	gun.ammo = 5
	shooter.input.reload = true
	await wait(0.05)
	shooter.input.reload = false
	check(gun.is_reloading(), "reload starts")
	await wait(Cfg.weapons.carbine.reload_time + 0.1)
	check(gun.ammo == Cfg.weapons.carbine.mag, "magazine is full")


func test_swapping_weapons_takes_time() -> void:
	shooter.input.weapon_slot = 1
	shooter.input.fire = true
	await wait(Cfg.weapon_swap_time - 0.1)
	check(shooter.arsenal.weapon().id == "pistol", "pistol is selected")
	check(shots_fired == 0, "cannot fire mid swap")
	shooter.input.fire = false
	await wait(0.2)
	await _pull_trigger()
	check(shots_fired == 1, "fires once the swap is done")


func test_sprinting_blocks_fire_then_delays_it() -> void:
	shooter.input.yaw = PI  # run away from the range
	shooter.input.sprint = true
	shooter.input.move = Vector2(0, 1)
	shooter.input.fire = true
	await wait(0.6)
	check(shots_fired == 0, "no firing while sprinting")
	shooter.input.sprint = false
	shooter.input.move = Vector2.ZERO
	await wait(Cfg.sprint_fire_delay - 0.1)
	check(shots_fired == 0, "still lowering the weapon")
	await wait(0.3)
	shooter.input.fire = false
	check(shots_fired > 0, "fires after the delay")


func test_recoil_kicks_up_and_settles() -> void:
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	var rest := shooter.head.rotation.x
	await _pull_trigger()
	check(shooter.head.rotation.x > rest + deg_to_rad(0.5), "view kicks upward")
	await wait(2.0)
	check_near(shooter.head.rotation.x, rest, deg_to_rad(0.05), "view settles back")


## Highest recoil seen over the next `seconds`.
func _peak_recoil(seconds: float) -> float:
	var peak := 0.0
	for i in ceili(seconds * 60):
		await get_tree().physics_frame
		peak = maxf(peak, rad_to_deg(shooter.arsenal.recoil.y))
	return peak


func test_sustained_fire_climbs_then_holds() -> void:
	var stats: Dictionary = Cfg.weapons.carbine
	shooter.input.fire = true
	var first_shot := await _peak_recoil(0.05)
	await wait(1.0)
	var settled := await _peak_recoil(0.3)
	shooter.input.fire = false
	check_near(first_shot, stats.recoil_pitch_deg, 0.2, "the first shot kicks by the weapon's recoil")
	check(settled > first_shot * 1.3, "holding the trigger climbs higher (%.2f -> %.2f deg)" % [first_shot, settled])
	# Recovery balances the kick, so a long spray settles at a fixed offset instead of climbing forever.
	var ceiling: float = stats.recoil_pitch_deg / (1.0 - exp(-stats.fire_interval * Cfg.recoil_recovery_rate))
	check(settled < ceiling * 1.15, "and levels off at a peak near %.1f deg, got %.2f" % [ceiling, settled])


func test_moving_widens_spread_and_crouching_tightens_it() -> void:
	Cfg.weapons.carbine.spread_deg = 0.4
	Cfg.weapons.carbine.move_spread_deg = 3.0
	var still := shooter.arsenal.spread_deg()
	check_near(still, 0.4, 0.001, "standing still uses base spread")
	shooter.input.move = Vector2(1, 0)
	await wait(0.5)
	var walking := shooter.arsenal.spread_deg()
	check(walking > still + 1.0, "walking adds spread (%.2f)" % walking)
	shooter.input.move = Vector2.ZERO
	shooter.input.crouch = true
	await wait(0.5)
	check_near(shooter.arsenal.spread_deg(), 0.4 * Cfg.crouch_spread_mult, 0.001, "crouching tightens spread")


func test_cannot_shoot_yourself() -> void:
	shooter.input.pitch = -PI / 2
	await wait(0.05)
	await _pull_trigger()
	check(shots_fired == 1, "fired at the floor")
	check_near(shooter.health, Cfg.max_health, 0.01, "no self damage")


func test_leaning_moves_the_head_hitbox() -> void:
	var target := _spawn(RANGE)
	target.input.lean = 1.0
	await wait(0.4)
	# Where the head used to be: nothing there now.
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health, 0.01, "upright head position is empty while leaning")
	# Where the head is now.
	await wait(1.0)
	await look_at_point(shooter, RANGE + Vector3(Cfg.lean_offset, HEAD_Y, 0))
	await _pull_trigger()
	check(target.is_dead, "the leaned head can be shot")


func test_crouching_lowers_the_head_hitbox() -> void:
	var target := _spawn(RANGE)
	target.input.crouch = true
	await wait(0.5)
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check_near(target.health, Cfg.max_health, 0.01, "standing head height is empty while crouched")
	await wait(1.0)
	await look_at_point(shooter, RANGE + Vector3(0, Cfg.crouch_height - Cfg.eye_drop, 0))
	await _pull_trigger()
	check(target.is_dead, "the crouched head can be shot")


func test_downed_player_blocks_nothing() -> void:
	var front := _spawn(Vector3(0, 0, -3))
	var behind := _spawn(Vector3(0, 0, -6))
	await look_at_point(shooter, Vector3(0, HEAD_Y, -3))
	await _pull_trigger()
	check(front.is_dead, "front target is down")
	await wait(1.0)
	await look_at_point(shooter, Vector3(0, CHEST_Y, -6))
	await _pull_trigger()
	check(behind.health < Cfg.max_health, "bullets pass over a downed player")
	check(front.health == 0.0, "a downed player takes no more hits")
	check(await walk_to(shooter, Vector3(0, 0, -4.5), 4.0), "can walk through a downed player")
	front.input.move = Vector2(0, 1)
	await wait(0.5)
	check_near(front.global_position.z, -3.0, 0.01, "a downed player cannot move")


func test_respawn_restores_everything() -> void:
	var target := _spawn(RANGE)
	target.arsenal.weapon().ammo = 0
	await look_at_point(shooter, RANGE + Vector3(0, HEAD_Y, 0))
	await _pull_trigger()
	check(target.is_dead, "target is down")
	target.respawn(Transform3D(Basis.IDENTITY, Vector3(2, 0, -5)))
	check(not target.is_dead and target.health == Cfg.max_health, "alive at full health")
	check(target.arsenal.weapon().ammo == Cfg.weapons.pistol.mag, "ammo refilled")
	await wait(1.0)
	await look_at_point(shooter, Vector3(2, CHEST_Y, -5))
	await _pull_trigger()
	check(target.health < Cfg.max_health, "can be hit again after respawn")


func test_shotgun_is_lethal_up_close_and_weak_at_range() -> void:
	Cfg.weapons.shotgun.spread_deg = 4.0
	var near := _spawn(Vector3(0, 0, -2))
	var far := _spawn(Vector3(3, 0, -12))
	await _select(2)
	await look_at_point(shooter, Vector3(0, CHEST_Y, -2))
	await _pull_trigger()
	check(near.is_dead, "one blast at 2 m kills (health %.0f)" % near.health)
	var armored := _spawn(Vector3(-3, 0, -2))
	armored.team = Team.Id.ENTRY
	await wait(1.0)
	await look_at_point(shooter, Vector3(-3, CHEST_Y, -2))
	await _pull_trigger()
	check(armored.is_dead, "one blast at 2 m kills through Entry armor too (health %.0f)" % armored.health)
	await wait(1.0)
	await look_at_point(shooter, Vector3(3, CHEST_Y, -12))
	await _pull_trigger()
	check(far.health > Cfg.max_health * 0.5, "one blast at 12 m does not come close (health %.0f)" % far.health)


func test_falloff_curve() -> void:
	var stats: Dictionary = Cfg.weapons.shotgun
	check_near(Ballistics.falloff(stats, 0.0), 1.0, 0.001, "full damage up close")
	check_near(Ballistics.falloff(stats, stats.falloff_start), 1.0, 0.001, "full damage at falloff start")
	check_near(Ballistics.falloff(stats, stats.falloff_end + 5.0), stats.falloff_min, 0.001, "minimum beyond falloff end")
	var mid: float = (stats.falloff_start + stats.falloff_end) * 0.5
	check_near(Ballistics.falloff(stats, mid), (1.0 + stats.falloff_min) * 0.5, 0.001, "linear in between")


func test_spread_stays_inside_its_cone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var aim := Vector3(0.3, 0.1, -1).normalized()
	var widest := 0.0
	for i in 500:
		widest = maxf(widest, rad_to_deg(aim.angle_to(Ballistics.spread(aim, 4.0, rng))))
	check(widest <= 4.001, "no pellet outside the cone (%.3f)" % widest)
	check(widest > 3.5, "pellets use the whole cone (%.3f)" % widest)
