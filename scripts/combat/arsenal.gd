class_name Arsenal
extends Node
## A player's weapons: trigger logic, ammo, reloads, spread and recoil.
## The owner runs the trigger and picks each pellet's direction. Only the server turns
## a shot into damage: `resolve` for its own players, `accept_remote_shot` for clients'.

## `shots` is an Array of {to: Vector3, hit: bool}, one per pellet.
signal fired(weapon: Weapon, from: Vector3, shots: Array)
signal hit_landed(zone: Hitbox.Zone, killed: bool)

var slots: Array[Weapon] = []
var current := 0
## View kick in radians: x = yaw, y = pitch (positive is up). Added on top of the look angles.
var recoil := Vector2.ZERO
var rng := RandomNumberGenerator.new()
## Weapons cannot fire while safe (setup phase, round end).
var safe := false

## How far a client's claimed eye position may be from where the server sees it (metres).
const REMOTE_ORIGIN_SLACK := 1.5
## Shots a client may deliver in one burst when the network bunches them up.
const REMOTE_BURST := 3.0

var _player: Player
var _trigger_was_down := false
var _swap_left := 0.0
var _sprint_lock := 0.0


func _init(player: Player) -> void:
	_player = player


func equip(weapon_ids: Array[String]) -> void:
	slots.clear()
	for id in weapon_ids:
		slots.append(Weapon.new(id))
	current = 0
	_player.input.weapon_slot = 0


func weapon() -> Weapon:
	return slots[current] if current < slots.size() else null


func refill_all() -> void:
	for slot in slots:
		slot.refill()
	recoil = Vector2.ZERO


## Cone half-angle of the next shot, given how the player is moving right now.
func spread_deg() -> float:
	if weapon() == null:
		return 0.0
	var stats := weapon().stats()
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var spread: float = stats.spread_deg + stats.move_spread_deg * clampf(speed / Cfg.sprint_speed, 0.0, 1.0)
	if _player.is_crouching():
		spread *= Cfg.crouch_spread_mult
	return spread


func tick(delta: float) -> void:
	recoil *= exp(-Cfg.recoil_recovery_rate * delta)
	var gun := weapon()
	if gun == null or _player.is_dead:
		return
	var input := _player.input

	if input.weapon_slot != current and input.weapon_slot >= 0 and input.weapon_slot < slots.size():
		gun.reload_left = 0.0  # swapping abandons a reload in progress
		current = input.weapon_slot
		gun = weapon()
		_swap_left = Cfg.weapon_swap_time
	_swap_left = maxf(_swap_left - delta, 0.0)

	# Sprinting lowers the weapon; it takes a moment to bring it back up.
	_sprint_lock = Cfg.sprint_fire_delay if _player.is_sprinting() else maxf(_sprint_lock - delta, 0.0)

	gun.cooldown = maxf(gun.cooldown - delta, -delta)
	if gun.is_reloading():
		gun.reload_left -= delta
		if gun.reload_left <= 0.0:
			gun.refill()

	var stats := gun.stats()
	var pulled: bool = input.fire and (stats.auto or not _trigger_was_down)
	_trigger_was_down = input.fire
	var ready := _swap_left <= 0.0 and _sprint_lock <= 0.0 and not gun.is_reloading()

	if ready and gun.ammo < stats.mag and (input.reload or (pulled and gun.ammo == 0)):
		gun.reload_left = stats.reload_time
	elif ready and pulled and gun.cooldown <= 0.0 and gun.ammo > 0 and not safe:
		_shoot(gun)


func _shoot(gun: Weapon) -> void:
	var stats := gun.stats()
	gun.ammo -= 1
	gun.cooldown += stats.fire_interval

	var from := _player.camera.global_position
	var aim := -_player.camera.global_basis.z
	var cone := spread_deg()
	var directions: Array[Vector3] = []
	for i: int in stats.pellets:
		directions.append(Ballistics.spread(aim, cone, rng))
	recoil.y += deg_to_rad(stats.recoil_pitch_deg)
	recoil.x += deg_to_rad(stats.recoil_yaw_deg) * rng.randf_range(-1.0, 1.0)

	if multiplayer.is_server():
		resolve(gun, from, directions)
	else:
		# Not the authority: draw the shot now and let the server decide what it hit.
		fired.emit(gun, from, _trace(gun, from, directions, false).shots)
		_player.send_shot(current, from, directions)


## Server only: applies one shot's damage and reports it.
func resolve(gun: Weapon, from: Vector3, directions: Array[Vector3]) -> void:
	var result := _trace(gun, from, directions, true)
	fired.emit(gun, from, result.shots)
	if result.hit:
		hit_landed.emit(result.zone, result.kill)


## Server only: a client says its player fired. Checked against what the server knows before it counts.
func accept_remote_shot(slot: int, from: Vector3, directions: Array) -> void:
	if _player.is_dead or safe or slot < 0 or slot >= slots.size():
		return
	var gun := slots[slot]
	var stats := gun.stats()
	if directions.size() != stats.pellets \
			or from.distance_to(_player.camera.global_position) > REMOTE_ORIGIN_SLACK:
		return
	var checked: Array[Vector3] = []
	for direction: Variant in directions:
		if not direction is Vector3:
			return
		checked.append((direction as Vector3).normalized())

	# The server does not see reloads, so it infers them: a pause as long as a reload refills
	# the magazine. Fire rate is a budget that refills over time, so shots that arrive
	# bunched together by the network are not thrown away.
	var now := Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	var idle := now - gun.last_shot_time
	gun.last_shot_time = now
	if idle >= stats.reload_time * 0.8:
		gun.ammo = stats.mag
	gun.rate_credit = minf(gun.rate_credit + idle / stats.fire_interval, REMOTE_BURST)
	if gun.rate_credit < 1.0 or gun.ammo <= 0:
		return
	gun.rate_credit -= 1.0
	gun.ammo -= 1
	current = slot
	resolve(gun, from, checked)


## Casts every pellet. Returns {shots: [{to, hit}], hit, kill, zone}. Damage is applied only if asked.
func _trace(gun: Weapon, from: Vector3, directions: Array[Vector3], apply_damage: bool) -> Dictionary:
	var stats := gun.stats()
	var exclude := _player.body.hitbox_rids()
	var result := {shots = [], hit = false, kill = false, zone = Hitbox.Zone.BODY}
	for direction in directions:
		var hit := Ballistics.cast(_player.get_world_3d(), from, direction, exclude)
		result.shots.append({to = hit.position if hit else from + direction * Cfg.weapon_range, hit = not hit.is_empty()})
		var hitbox := hit.get("collider") as Hitbox
		if hitbox == null or not apply_damage:
			continue
		var damage: float = stats.damage * Ballistics.falloff(stats, from.distance_to(hit.position))
		result.kill = hitbox.target.take_hit(damage, hitbox.zone, _player) or result.kill
		result.hit = true
		if hitbox.zone == Hitbox.Zone.HEAD:
			result.zone = Hitbox.Zone.HEAD
	return result
