class_name Player
extends CharacterBody3D
## First-person controller. Origin is at the feet.
## All motion comes from `input`; set `controlled_locally` to false to drive it from code.

@export var controlled_locally := true

var input := PlayerInput.new()
## 0 = standing, 1 = fully crouched.
var crouch_frac := 0.0
## -1 = full left lean, +1 = full right lean (after wall clamping).
var lean_frac := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var _collider: CollisionShape3D = $Collider

var _capsule: CapsuleShape3D
var _probe := SphereShape3D.new()


func _ready() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Cfg.body_radius
	_collider.shape = _capsule
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.PLAYER
	floor_snap_length = 0.3
	camera.current = controlled_locally
	_apply_body_shape()
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if not controlled_locally:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := deg_to_rad(Cfg.mouse_sensitivity_deg)
		input.yaw = wrapf(input.yaw - event.relative.x * sens, -PI, PI)
		input.pitch -= event.relative.y * sens
	elif event.is_action_pressed("interact"):
		use_door(Door.Action.TOGGLE_OPEN)
	elif event.is_action_pressed("door_crack"):
		use_door(Door.Action.TOGGLE_CRACK)


func _physics_process(delta: float) -> void:
	if controlled_locally:
		_read_local_input()
	simulate(delta)


func _read_local_input() -> void:
	input.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	input.sprint = Input.is_action_pressed("sprint")
	input.crouch = Input.is_action_pressed("crouch")
	input.lean = Input.get_axis("lean_left", "lean_right")


func simulate(delta: float) -> void:
	var limit := deg_to_rad(Cfg.pitch_limit_deg)
	input.pitch = clampf(input.pitch, -limit, limit)
	rotation.y = input.yaw
	_update_crouch(delta)
	_update_lean(delta)
	_update_velocity(delta)
	move_and_slide()
	_apply_view()


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
	return speed


## The door under the crosshair within reach, or null.
func aimed_door() -> Door:
	var from := camera.global_position
	var to := from - camera.global_basis.z * Cfg.interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider.get_parent() as Door


func use_door(action: Door.Action) -> bool:
	var door := aimed_door()
	if door == null:
		return false
	door.interact(action, global_position)
	return true


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
	head.position = Vector3(lean_frac * Cfg.lean_offset, _eye_height(), 0.0)
	head.rotation.x = input.pitch
	camera.rotation.z = -lean_frac * deg_to_rad(Cfg.lean_roll_deg)


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
