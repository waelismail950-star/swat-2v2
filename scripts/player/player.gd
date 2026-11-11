class_name Player
extends CharacterBody3D
## One player's body. Origin is at the feet.
##
## Networking: the peer that owns a player (its multiplayer authority) simulates it from
## `input` and broadcasts the result; every other peer shows a smoothed copy. Health,
## hits, and everything the player does to the world are decided by the server.

signal died(victim: Player, killer: Node)
signal health_changed(player: Player)
signal respawned(player: Player)

## Eye height of a downed player's camera.
const DOWNED_EYE := 0.35
## How quickly a remote copy closes on the latest received state, per second.
const NET_SMOOTHING := 25.0
## A remote copy further than this from its target jumps instead of gliding.
const NET_SNAP_DISTANCE := 3.0
## Extra reach the server allows a remote player's interaction, for latency.
const NET_REACH_SLACK := 1.5

## True for the one player driven by this machine's keyboard and seen in first person.
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
## Whether the owner sends its state to other peers. Off until every peer has the world built.
var broadcasting := false

## Physics ticks left during which the body holds still after a respawn.
var _settle_ticks := 0
var _interact_was_down := false
var _crack_was_down := false
## What this player is holding interact on. On the server, for remote players, this is what they asked to hold.
var _hold_target: Node

# Latest state received from the owner (remote copies only).
var _net_position := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_crouch := 0.0
var _net_lean := 0.0

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
	_hold_target = null
	_net_position = at.origin
	_net_yaw = rotation.y
	_net_pitch = 0.0
	_net_crouch = 0.0
	_net_lean = 0.0
	_apply_body_shape()
	_apply_view()
	respawned.emit(self)


## Puts the player on a side: colour, weapons and side-specific stats follow from it.
func assign_team(new_team: Team.Id) -> void:
	team = new_team
	body.set_color(Team.COLORS[team])
	var loadout: Array[String] = []
	loadout.assign(Team.LOADOUTS[team])
	arsenal.equip(loadout)


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
	if not is_multiplayer_authority():
		_follow_owner(delta)
		return
	if controlled_locally:
		_read_local_input()
	elif brain != null:
		brain.think(delta)
	simulate(delta)
	if broadcasting:
		_net_state.rpc(global_position, rotation.y, input.pitch, crouch_frac, lean_frac, velocity, arsenal.current)


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


## Advances the player one tick from `input`. Only the owner calls this.
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


# --- Health (server decides) ---

## Called by weapons, on the server only. Returns true if this hit downed the player.
func take_hit(damage: float, zone: Hitbox.Zone, shooter: Node) -> bool:
	if is_dead:
		return false
	if zone == Hitbox.Zone.HEAD:
		damage *= Cfg.headshot_mult
	elif team == Team.Id.ENTRY:
		damage *= Cfg.entry_body_damage_mult
	health = maxf(health - damage, 0.0)
	if health <= 0.0:
		_go_down(shooter)
	health_changed.emit(self)
	return is_dead


## Applies the server's word on this player's health (clients only).
func set_health_from_server(new_health: float, dead: bool) -> void:
	health = new_health
	if dead and not is_dead:
		_go_down(null)


func _go_down(killer: Node) -> void:
	is_dead = true
	velocity = Vector3.ZERO
	collision_layer = 0  # a downed player blocks nobody
	_hold_target = null
	body.set_alive(false)
	_apply_view()
	died.emit(self, killer)


# --- Shooting ---

## Asks the server to resolve a shot this player just fired (owner on a client only).
func send_shot(slot: int, from: Vector3, directions: Array[Vector3]) -> void:
	_net_fire.rpc_id(1, slot, from, directions)


## Draws tracers for a shot by this player.
func show_shots(from: Vector3, shots: Array) -> void:
	# Tracers start at the gun, not the eye, so they do not cover the crosshair.
	var muzzle := from + camera.global_basis * Vector3(0.15, -0.12, -0.5)
	for shot: Dictionary in shots:
		ShotFx.tracer(get_parent(), muzzle, shot.to, shot.hit)


func _on_fired(_weapon: Weapon, from: Vector3, shots: Array) -> void:
	show_shots(from, shots)


# --- Interaction ---

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
	_use(aimed_interactable(), false)


func press_crack() -> void:
	_use(aimed_interactable(), true)


## Acts on `target` directly on the server, or asks the server to.
func _use(target: Node, crack: bool) -> void:
	if target == null or (crack and not target.has_method("on_crack")):
		return
	if not multiplayer.is_server():
		_net_use.rpc_id(1, get_parent().get_path_to(target), crack)
	elif crack:
		target.on_crack(self)
	else:
		target.on_interact(self)


func _update_interaction(delta: float) -> void:
	if input.interact and not _interact_was_down:
		press_interact()
	if input.crack and not _crack_was_down:
		press_crack()
	_interact_was_down = input.interact
	_crack_was_down = input.crack

	var holding: Node = aimed_interactable() if input.interact else null
	if holding != null and not holding.has_method("on_interact_hold"):
		holding = null
	if multiplayer.is_server():
		if holding != null:
			holding.on_interact_hold(self, delta)
	elif holding != _hold_target:
		_net_hold.rpc_id(1, get_parent().get_path_to(holding) if holding != null else NodePath())
	_hold_target = holding


## Server-side check on a remote player's claim to be interacting with `target`.
func _can_reach(target: Node) -> bool:
	return not is_dead and target is Node3D and target.has_method("interact_prompt") \
			and camera.global_position.distance_to((target as Node3D).global_position) \
			<= Cfg.interact_range + NET_REACH_SLACK


# --- Network messages ---
# "authority" means only this player's owner may send the message.

## Owner -> everyone: where I am.
@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(at: Vector3, yaw: float, pitch: float, crouch: float, lean: float,
		speed: Vector3, weapon_slot: int) -> void:
	_net_position = at
	_net_yaw = yaw
	_net_pitch = pitch
	_net_crouch = crouch
	_net_lean = lean
	velocity = speed
	if weapon_slot >= 0 and weapon_slot < arsenal.slots.size():
		arsenal.current = weapon_slot


## Owner -> server: I fired.
@rpc("authority", "call_remote", "reliable")
func _net_fire(slot: int, from: Vector3, directions: Array) -> void:
	if multiplayer.is_server():
		arsenal.accept_remote_shot(slot, from, directions)


## Owner -> server: I pressed interact (or crack) on this node. `path` is relative to the world.
@rpc("authority", "call_remote", "reliable")
func _net_use(path: NodePath, crack: bool) -> void:
	var target := get_parent().get_node_or_null(path)
	if multiplayer.is_server() and _can_reach(target):
		if not crack:
			target.on_interact(self)
		elif target.has_method("on_crack"):
			target.on_crack(self)


## Owner -> server: I am holding interact on this node (empty path = let go).
@rpc("authority", "call_remote", "reliable")
func _net_hold(path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var target := get_parent().get_node_or_null(path) if not path.is_empty() else null
	_hold_target = target if target != null and target.has_method("on_interact_hold") else null


## Non-owners: glide toward the owner's latest state.
func _follow_owner(delta: float) -> void:
	var blend := 1.0 - exp(-NET_SMOOTHING * delta)
	if global_position.distance_to(_net_position) > NET_SNAP_DISTANCE:
		global_position = _net_position
	else:
		global_position = global_position.lerp(_net_position, blend)
	rotation.y = lerp_angle(rotation.y, _net_yaw, blend)
	input.yaw = rotation.y
	input.pitch = lerpf(input.pitch, _net_pitch, blend)
	crouch_frac = lerpf(crouch_frac, _net_crouch, blend)
	lean_frac = lerpf(lean_frac, _net_lean, blend)
	_apply_body_shape()
	_apply_view()
	# The server keeps a remote player's hold going for as long as they stay in reach.
	if multiplayer.is_server() and _hold_target != null:
		if _can_reach(_hold_target):
			_hold_target.on_interact_hold(self, delta)
		else:
			_hold_target = null


# --- Movement internals ---

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
