class_name Hostage
extends CharacterBody3D
## The hostage. Restrained and stationary until an Entry operator secures them, then
## walks a fixed list of waypoints to the extraction point while an operator stays close.

enum State { HELD, FOLLOWING, EXTRACTED, DEAD }

signal secured(by: Player)
signal killed(by: Node)
signal extracted

const HELD_HEIGHT := 1.2      # kneeling
const FOLLOW_HEIGHT := 1.7
const COLOR := Color(0.95, 0.85, 0.2)
const ARRIVE_DISTANCE := 0.3

var state := State.HELD
var health := 0.0
## Seconds of uninterrupted holding so far.
var secure_progress := 0.0
var path: Array[Vector3] = []

var _path_index := 0
var _last_hold_frame := -10
var _body := PlayerBody.new()
var _reach := Area3D.new()


func _ready() -> void:
	collision_layer = 0  # nobody bumps into the hostage; only bullets and the interact ray find them
	collision_mask = Layers.WORLD
	floor_snap_length = 0.3
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = HELD_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = HELD_HEIGHT * 0.5
	add_child(collider)

	add_child(_body)
	_body.setup(self)
	_body.set_color(COLOR)

	var reach_shape := CapsuleShape3D.new()
	reach_shape.radius = 0.35
	reach_shape.height = FOLLOW_HEIGHT
	var reach_collider := CollisionShape3D.new()
	reach_collider.shape = reach_shape
	reach_collider.position.y = FOLLOW_HEIGHT * 0.5
	_reach.add_child(reach_collider)
	_reach.monitoring = false
	_reach.collision_mask = 0
	add_child(_reach)
	place(global_position, [])


## Resets the hostage, restrained, at `at`. `route` is the walk to extraction from there.
func place(at: Vector3, route: Array[Vector3]) -> void:
	global_position = at
	velocity = Vector3.ZERO
	path = route
	_path_index = 0
	state = State.HELD
	health = Cfg.hostage_health
	secure_progress = 0.0
	_reach.collision_layer = Layers.INTERACT
	_body.set_alive(true)
	_body.pose(HELD_HEIGHT, 0.0)


func interact_prompt(player: Player) -> String:
	if state == State.HELD and player.team == Team.Id.ENTRY:
		return "Hold [F] to secure the hostage  %d%%" % roundi(100.0 * secure_progress / Cfg.hostage_secure_time)
	return ""


func on_interact(_player: Player) -> void:
	pass  # securing needs a hold, not a tap


func on_interact_hold(player: Player, delta: float) -> void:
	if state != State.HELD or player.team != Team.Id.ENTRY:
		return
	secure_progress += delta
	_last_hold_frame = Engine.get_physics_frames()
	if secure_progress >= Cfg.hostage_secure_time:
		state = State.FOLLOWING
		_reach.collision_layer = 0
		_body.pose(FOLLOW_HEIGHT, 0.0)
		secured.emit(player)


## Any direct hit counts; splash and flash never call this.
func take_hit(damage: float, _zone: Hitbox.Zone, shooter: Node) -> bool:
	if state == State.DEAD or state == State.EXTRACTED:
		return false
	health -= damage
	if health > 0.0:
		return false
	state = State.DEAD
	velocity = Vector3.ZERO
	_reach.collision_layer = 0
	_body.set_alive(false)
	killed.emit(shooter)
	return true


## The point the hostage is walking toward, or its own position if it has nowhere to go.
func next_waypoint() -> Vector3:
	return path[_path_index] if _path_index < path.size() else global_position


func is_escorted() -> bool:
	for player: Player in get_tree().get_nodes_in_group(Player.GROUP):
		if player.team == Team.Id.ENTRY and not player.is_dead \
				and player.global_position.distance_to(global_position) <= Cfg.hostage_follow_radius:
			return true
	return false


func _physics_process(delta: float) -> void:
	if state == State.HELD:
		# Letting go of the key loses all progress.
		if Engine.get_physics_frames() - _last_hold_frame > 1:
			secure_progress = 0.0
		return
	if state != State.FOLLOWING:
		return

	var step := Vector3.ZERO
	if is_escorted() and _path_index < path.size():
		var to := path[_path_index] - global_position
		to.y = 0.0
		if to.length() < ARRIVE_DISTANCE:
			_path_index += 1
			if _path_index >= path.size():
				state = State.EXTRACTED
				extracted.emit()
				return
		else:
			step = to.normalized() * Cfg.hostage_speed
	velocity.x = step.x
	velocity.z = step.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - Cfg.gravity * delta
	move_and_slide()
