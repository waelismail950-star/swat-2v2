class_name Arsenal
extends Node
## A player's weapons: trigger logic, ammo, reloads, spread and recoil.
## Each shot is resolved here by raycast; this is the server-side authority boundary in multiplayer.

## `shots` is an Array of {to: Vector3, hit: bool}, one per pellet.
signal fired(weapon: Weapon, from: Vector3, shots: Array)
signal hit_landed(zone: Hitbox.Zone, killed: bool)

var slots: Array[Weapon] = []
var current := 0
## View kick in radians: x = yaw, y = pitch (positive is up). Added on top of the look angles.
var recoil := Vector2.ZERO
var rng := RandomNumberGenerator.new()

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
	elif ready and pulled and gun.cooldown <= 0.0 and gun.ammo > 0:
		_shoot(gun)


func _shoot(gun: Weapon) -> void:
	var stats := gun.stats()
	gun.ammo -= 1
	gun.cooldown += stats.fire_interval

	var from := _player.camera.global_position
	var aim := -_player.camera.global_basis.z
	var cone := spread_deg()
	var exclude := _player.body.hitbox_rids()
	var shots := []
	var best_zone := Hitbox.Zone.BODY
	var any_hit := false
	var any_kill := false
	for i: int in stats.pellets:
		var direction := Ballistics.spread(aim, cone, rng)
		var hit := Ballistics.cast(_player.get_world_3d(), from, direction, exclude)
		shots.append({to = hit.position if hit else from + direction * Cfg.weapon_range, hit = not hit.is_empty()})
		var hitbox := hit.get("collider") as Hitbox
		if hitbox == null:
			continue
		var damage: float = stats.damage * Ballistics.falloff(stats, from.distance_to(hit.position))
		any_kill = hitbox.target.take_hit(damage, hitbox.zone, _player) or any_kill
		any_hit = true
		if hitbox.zone == Hitbox.Zone.HEAD:
			best_zone = Hitbox.Zone.HEAD

	recoil.y += deg_to_rad(stats.recoil_pitch_deg)
	recoil.x += deg_to_rad(stats.recoil_yaw_deg) * rng.randf_range(-1.0, 1.0)
	fired.emit(gun, from, shots)
	if any_hit:
		hit_landed.emit(best_zone, any_kill)
