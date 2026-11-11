class_name Player
extends CharacterBody3D
## First-person controller. Origin is at the feet.
## All motion comes from `input`; set `controlled_locally` to false to drive it from code.

signal died(victim: Player, killer: Node)

## Eye height of a downed player's camera.
const DOWNED_EYE := 0.35
## Scene-tree group every player joins.
const GROUP := &"players"

@export var controlled_locally := true

var input := PlayerInput.new()
## 0 = standing, 1 = fully crouched.
var crouch_frac := 0.0
## -1 = full left lean, +1 = full right lean (after wall clamping).
var lean_frac := 0.0
var health := 0.0
var is_dead := false
var arsenal := Arsenal.new(self)
var team := Team.Id.ENTRY
## Which of the two groups of players this one belongs to for the whole match.
var roster := 0
var display_name := ""
## Set for bots: fills `input` each tick instead of the keyboard.
var brain: Bot

## Physics ticks left during which the body holds still after a respawn.
var _settle_ticks := 0
var _interact_was_down := false
var _crack_was_down := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var body: PlayerBody = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _viewmodel: Viewmodel = $Head/Camera/Viewmodel

var _capsule: CapsuleShape3D
var _probe := SphereShape3D.new()


func _ready() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Cfg.body_radius
	_collider.shape = _capsule
	collision_mask = Layers.WORLD | Layers.PLAYER
	floor_snap_length = 0.3
	# Nothing in the game is a moving platform. Leaving these on lets a teleporting player
	# (round reset) or a swinging door fling whoever it touches.
	platform_floor_layers = 0
	platform_wall_layers = 0
	add_to_group(GROUP)
	add_child(arsenal)
	arsenal.fired.connect(_on_fired)
	body.setup(self)
	body.set_first_person(controlled_locally)
	_viewmodel.visible = controlled_locally
	camera.current = controlled_locally
	respawn(global_transform)


## Puts the player back on their feet at `at` with full health and ammo.
func respawn(at: Transform3D) -> void:
	global_transform = at
	input.yaw = rotation.y
	input.pitch = 0.0
	velocity = Vector3.ZERO
	crouch_frac = 0.0
	lean_frac = 0.0
	health = Cfg.max_health
	is_dead = false
	collision_layer = Layers.PLAYER
	body.set_alive(true)
	arsenal.refill_all()
	# Teleports reach the physics server a tick late. Moving before then would collide with
	# wherever the other players used to stand and pop this one into the air.
	_settle_ticks = 2
	_apply_body_shape()
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if not controlled_locally or is_dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := deg_to_rad(Cfg.mouse_sensitivity_deg)
		input.yaw = wrapf(input.yaw - event.relative.x * sens, -PI, PI)
		input.pitch -= event.relative.y * sens
	else:
		for slot in arsenal.slots.size():
			if event.is_action_pressed("weapon_%d" % (slot + 1)):
				input.weapon_slot = slot


func _physics_process(delta: float) -> void:
	if controlled_locally:
		_read_local_input()
	elif brain != null:
		brain.think(delta)
	simulate(delta)


## Puts the player on a side: colour, weapons and side-specific stats follow from it.
func assign_team(new_team: Team.Id) -> void:
	team = new_team
	body.set_color(Team.COLORS[team])
	var loadout: Array[String] = []
	loadout.assign(Team.LOADOUTS[team])
	arsenal.equip(loadout)


func _read_local_input() -> void:
	input.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	input.sprint = Input.is_action_pressed("sprint")
	input.crouch = Input.is_action_pressed("crouch")
	input.lean = Input.get_axis("lean_left", "lean_right")
	input.reload = Input.is_action_pressed("reload")
	input.interact = Input.is_action_pressed("interact")
	input.crack = Input.is_action_pressed("door_crack")
	# The click that captures the mouse must not also fire.
	input.fire = Input.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func simulate(delta: float) -> void:
	if _settle_ticks > 0:
		_settle_ticks -= 1
	elif not is_dead:
		var limit := deg_to_rad(Cfg.pitch_limit_deg)
		input.pitch = clampf(input.pitch, -limit, limit)
		rotation.y = input.yaw
		_update_crouch(delta)
		_update_lean(delta)
		_update_velocity(delta)
		move_and_slide()
		_update_interaction(delta)
	_apply_view()
	arsenal.tick(delta)
	if controlled_locally:
		_viewmodel.update(arsenal)


func is_crouching() -> bool:
	return crouch_frac > 0.5


func is_sprinting() -> bool:
	return input.sprint and input.move.y > 0.1 and input.lean == 0.0 \
			and not input.crouch and crouch_frac < 0.01


func current_height() -> float:
	return lerpf(Cfg.stand_height, Cfg.crouch_height, crouch_frac)


func max_speed() -> float:
	var speed := Cfg.walk_speed
	if crouch_frac > 0.01:
		speed = lerpf(Cfg.walk_speed, Cfg.crouch_speed, crouch_frac)
	elif is_sprinting():
		speed = Cfg.sprint_speed
	if input.lean != 0.0:
		speed *= Cfg.lean_move_mult
	if team == Team.Id.SUSPECTS:
		speed *= Cfg.suspect_speed_mult
	return speed


## Called by weapons. Returns true if this hit killed the player.
func take_hit(damage: float, zone: Hitbox.Zone, shooter: Node) -> bool:
	if is_dead:
		return false
	if zone == Hitbox.Zone.HEAD:
		damage *= Cfg.headshot_mult
	elif team == Team.Id.ENTRY:
		damage *= Cfg.entry_body_damage_mult
	health = maxf(health - damage, 0.0)
	if health > 0.0:
		return false
	is_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0  # a downed player blocks nobody
	body.set_alive(false)
	_apply_view()
	died.emit(self, shooter)
	return true


## The thing under the crosshair within reach that can be interacted with, or null.
## Interactables are nodes with interact_prompt(player) and on_interact(player);
## optionally on_interact_hold(player, delta) and on_crack(player).
func aimed_interactable() -> Node:
	var from := camera.global_position
	var to := from - camera.global_basis.z * Cfg.interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD | Layers.INTERACT)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider")
	while node != null and not node.has_method("interact_prompt"):
		node = node.get_parent()
	return node


func press_interact() -> void:
	var target := aimed_interactable()
	if target != null:
		target.on_interact(self)


func press_crack() -> void:
	var target := aimed_interactable()
	if target != null and target.has_method("on_crack"):
		target.on_crack(self)


func _update_interaction(delta: float) -> void:
	if input.interact:
		if not _interact_was_down:
			press_interact()
		var target := aimed_interactable()
		if target != null and target.has_method("on_interact_hold"):
			target.on_interact_hold(self, delta)
	if input.crack and not _crack_was_down:
		press_crack()
	_interact_was_down = input.interact
	_crack_was_down = input.crack


func _update_crouch(delta: float) -> void:
	var target := 1.0 if input.crouch else 0.0
	# Standing up is refused while something solid is overhead.
	if target < crouch_frac and not _has_headroom():
		return
	crouch_frac = move_toward(crouch_frac, target, delta / Cfg.crouch_time)
	_apply_body_shape()


func _has_headroom() -> bool:
	var rise := Cfg.stand_height - current_height()
	if rise <= 0.0:
		return true
	var r := Cfg.body_radius * 0.9
	var from := global_position + Vector3.UP * (current_height() - Cfg.body_radius)
	return _sweep(r, from, Vector3.UP * rise) >= 1.0


func _update_lean(delta: float) -> void:
	var eye := global_position + Vector3.UP * _eye_height()
	var right := global_basis.x * Cfg.lean_offset
	var room_right := _sweep(Cfg.lean_head_radius, eye, right)
	var room_left := _sweep(Cfg.lean_head_radius, eye, -right)
	var want := clampf(input.lean, -1.0, 1.0)
	lean_frac = move_toward(lean_frac, want, delta / Cfg.lean_time)
	# Hard clamp so the camera can never be pushed through geometry.
	lean_frac = clampf(lean_frac, -room_left, room_right)


func _update_velocity(delta: float) -> void:
	var move := input.move.limit_length(1.0)
	var wish := global_basis * Vector3(move.x, 0.0, -move.y) * max_speed()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := Cfg.ground_accel if move != Vector2.ZERO else Cfg.ground_decel
	horizontal = horizontal.move_toward(wish, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= Cfg.gravity * delta


func _eye_height() -> float:
	return current_height() - Cfg.eye_drop


func _apply_body_shape() -> void:
	var h := current_height()
	_capsule.height = h
	_collider.position.y = h * 0.5


func _apply_view() -> void:
	if is_dead:
		head.position = Vector3(0.0, DOWNED_EYE, 0.0)
		return
	var limit := deg_to_rad(Cfg.pitch_limit_deg)
	head.position = Vector3(lean_frac * Cfg.lean_offset, _eye_height(), 0.0)
	head.rotation.x = clampf(input.pitch + arsenal.recoil.y, -limit, limit)
	head.rotation.y = arsenal.recoil.x
	camera.rotation.z = -lean_frac * deg_to_rad(Cfg.lean_roll_deg)
	body.pose(current_height(), lean_frac)


func _on_fired(_weapon: Weapon, from: Vector3, shots: Array) -> void:
	# Tracers start at the gun, not the eye, so they do not cover the crosshair.
	var muzzle := from + camera.global_basis * Vector3(0.15, -0.12, -0.5)
	for shot: Dictionary in shots:
		ShotFx.tracer(get_parent(), muzzle, shot.to, shot.hit)


## Sweeps a sphere through the world and returns the fraction of `motion` that is free (0..1).
func _sweep(radius: float, from: Vector3, motion: Vector3) -> float:
	_probe.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = motion
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.cast_motion(query)[0]
