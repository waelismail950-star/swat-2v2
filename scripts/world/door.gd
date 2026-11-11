class_name Door
extends Node3D
## A hinged door. The node sits at the hinge; local +X runs along the closed panel
## toward the latch. `state` and `swing_sign` are the authoritative data; the panel
## angle is derived from them and animated locally.

enum State { CLOSED, CRACKED, OPEN }
enum Action { TOGGLE_OPEN, TOGGLE_CRACK }

signal state_changed(door: Door)

const PANEL_THICKNESS := 0.05
const EDGE_GAP := 0.03
const PANEL_COLOR := Color(0.6, 0.4, 0.22)

var door_name := ""
var width := 1.0
var height := 2.1

var state := State.CLOSED
## +1 swings the panel toward local -Z, -1 toward local +Z.
var swing_sign := 1.0
var angle_deg := 0.0

var _panel: AnimatableBody3D
## Thinner than the real panel so a body merely touching the door does not count as in the way.
var _probe := BoxShape3D.new()


func _ready() -> void:
	var size := Vector3(width - 2.0 * EDGE_GAP, height - EDGE_GAP, PANEL_THICKNESS)
	_probe.size = Vector3(size.x, size.y - 0.2, 0.01)

	_panel = AnimatableBody3D.new()
	_panel.sync_to_physics = false
	_panel.collision_layer = Layers.WORLD
	_panel.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = _panel_center()
	_panel.add_child(collider)
	Greybox.add_visual(_panel, _panel_center(), size, PANEL_COLOR)
	add_child(_panel)


## Applies a door action. `from` is where the operator stands (world space).
func interact(action: Action, from: Vector3) -> void:
	var next := _next_state(action)
	if next != State.CLOSED:
		swing_sign = _pick_swing_sign(from)
	state = next
	state_changed.emit(self)


func target_angle_deg() -> float:
	match state:
		State.CRACKED:
			return swing_sign * Cfg.door_crack_angle_deg
		State.OPEN:
			return swing_sign * Cfg.door_open_angle_deg
	return 0.0


func is_settled() -> bool:
	return is_equal_approx(angle_deg, target_angle_deg())


func _physics_process(delta: float) -> void:
	if is_settled():
		return
	var next := move_toward(angle_deg, target_angle_deg(), Cfg.door_swing_speed_deg * delta)
	# A body in the way stops the door; it carries on once the path is clear.
	if _panel_would_hit_player(next):
		return
	angle_deg = next
	_panel.rotation_degrees.y = angle_deg


func _next_state(action: Action) -> State:
	if action == Action.TOGGLE_OPEN:
		return State.CLOSED if state == State.OPEN else State.OPEN
	return State.CLOSED if state == State.CRACKED else State.CRACKED


## Doors swing away from whoever operates them. If someone is pressed against the far
## side the door swings toward the operator instead, so a door cannot be held shut by a body.
func _pick_swing_sign(from: Vector3) -> float:
	var away := 1.0 if to_local(from).z >= 0.0 else -1.0
	if _panel_would_hit_player(away * Cfg.door_crack_angle_deg * 1.5):
		return -away
	return away


func _panel_center() -> Vector3:
	return Vector3(width * 0.5, height * 0.5, 0.0)


func _panel_would_hit_player(at_angle_deg: float) -> bool:
	var swung := Transform3D(Basis(Vector3.UP, deg_to_rad(at_angle_deg)), Vector3.ZERO)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = global_transform * swung * Transform3D(Basis.IDENTITY, _panel_center())
	query.collision_mask = Layers.PLAYER
	query.margin = 0.0
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
