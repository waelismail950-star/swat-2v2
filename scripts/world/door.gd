class_name Door
extends Node3D
## A hinged door. The node sits at the hinge; local +X runs along the closed panel
## toward the latch. The two sides of the door are local +Z (side +1) and -Z (side -1).
##
## Everything in `snapshot()` is decided by the server. The panel angle is derived from
## it and animated on each machine.

enum State { CLOSED, CRACKED, OPEN }
enum Action { TOGGLE_OPEN, TOGGLE_CRACK }

## Something a client must mirror has changed.
signal state_changed(door: Door)
## An Entry operator set off the trip alarm on this door.
signal alarm_tripped(door: Door)
## A breaching charge went off. `charge_side` is the side it was placed on.
signal breached(door: Door, charge_side: float)

const PANEL_THICKNESS := 0.05
const EDGE_GAP := 0.03
const PANEL_COLOR := Color(0.6, 0.4, 0.22)
## How far into the room a trip alarm sits, and a door camera's lens.
const ALARM_INSET := 0.6
const SCOPE_INSET := 0.3

var door_name := ""
var width := 1.0
var height := 2.1

## A locked door ignores players (exterior doors during setup).
var locked := false

var state := State.CLOSED
## +1 swings the panel toward local -Z, -1 toward local +Z.
var swing_sign := 1.0
var angle_deg := 0.0

# Gadgets attached to this door. Sides are +1 / -1, 0 means not present.
## A wedged door stays shut until the wedge is removed, forced or blown.
var wedged := false
## Side a breaching charge is stuck to.
var charge_side := 0.0
## Side of the door a trip alarm sits on.
var alarm_side := 0.0
## Side a door camera's lens is poking out on.
var scope_side := 0.0

var _panel: AnimatableBody3D
## Thinner than the real panel so a body merely touching the door does not count as in the way.
var _probe := BoxShape3D.new()
var _fuse_left := 0.0
var _force_progress := 0.0
var _last_force_frame := -10
var _wedge_visual: MeshInstance3D
var _charge_visual: MeshInstance3D
var _scope_visual: MeshInstance3D
var _alarm: Node3D
var _alarm_hitbox: Hitbox
var _alarm_probe := SphereShape3D.new()


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

	_wedge_visual = Greybox.add_visual(self, Vector3.ZERO, Vector3(0.22, 0.07, 0.5), Color(0.95, 0.8, 0.1))
	_charge_visual = Greybox.add_visual(self, Vector3.ZERO, Vector3(0.16, 0.26, 0.05), Color(0.85, 0.1, 0.1))
	_scope_visual = Greybox.add_visual(self, Vector3.ZERO, Vector3(0.04, 0.04, 0.3), Color(0.05, 0.05, 0.05))
	_alarm = Node3D.new()
	add_child(_alarm)
	var alarm_size := Vector3(0.14, 0.12, 0.14)
	Greybox.add_visual(_alarm, Vector3.ZERO, alarm_size, Color(1.0, 0.45, 0.0))
	var alarm_shape := BoxShape3D.new()
	alarm_shape.size = alarm_size
	_alarm_hitbox = Hitbox.create(self, Hitbox.Zone.BODY, alarm_shape)
	_alarm.add_child(_alarm_hitbox)
	_show_gadgets()


# --- Interaction ---

func interact_prompt(player: Player) -> String:
	if locked:
		return "%s (locked)" % door_name
	if charge_side != 0.0:
		return "%s (charge set - stand clear)" % door_name
	if wedged:
		return "%s (wedged)\n%s" % [door_name, "[F] remove the wedge" if player.team == Team.Id.SUSPECTS
				else "Hold [F] for %d s to force it" % ceili(Cfg.wedge_force_time)]
	return "%s (%s)\n[F] %s    [V] %s" % [door_name, State.keys()[state].to_lower(),
			"close" if state == State.OPEN else "open",
			"close" if state == State.CRACKED else "crack"]


func on_interact(player: Player) -> void:
	if locked:
		return
	if wedged:
		if player.team == Team.Id.SUSPECTS:
			set_wedged(false)
		return
	interact(Action.TOGGLE_OPEN, player.global_position)


func on_crack(player: Player) -> void:
	if not locked:
		interact(Action.TOGGLE_CRACK, player.global_position)


## Holding interact on a wedged door forces it. Anyone can; it is slow and (from M7) loud.
func on_interact_hold(_player: Player, delta: float) -> void:
	if not wedged:
		return
	_force_progress += delta
	_last_force_frame = Engine.get_physics_frames()
	if _force_progress >= Cfg.wedge_force_time:
		set_wedged(false)


## Applies a door action. `from` is where the operator stands (world space). A wedged door ignores it.
func interact(action: Action, from: Vector3) -> void:
	if wedged:
		return
	var next := _next_state(action)
	if next != State.CLOSED:
		swing_sign = _pick_swing_sign(from)
	state = next
	state_changed.emit(self)


## Shuts the door instantly and strips every gadget (round reset). Does not emit state_changed.
func reset(lock: bool) -> void:
	locked = lock
	state = State.CLOSED
	angle_deg = 0.0
	_panel.rotation_degrees.y = 0.0
	wedged = false
	charge_side = 0.0
	alarm_side = 0.0
	scope_side = 0.0
	_fuse_left = 0.0
	_force_progress = 0.0
	_show_gadgets()


# --- Gadgets (server) ---

## +1 or -1: which side of the door a world-space point is on.
func side_of(point: Vector3) -> float:
	return 1.0 if to_local(point).z >= 0.0 else -1.0


## World-space point `distance` out from the middle of the doorway on `side`, `up` above the floor.
func side_point(side: float, distance: float, up: float) -> Vector3:
	return to_global(Vector3(width * 0.5, up, side * distance))


func is_shut() -> bool:
	return state == State.CLOSED and is_settled()


func set_wedged(value: bool) -> void:
	wedged = value
	_force_progress = 0.0
	_changed()


func place_charge(side: float) -> void:
	charge_side = side
	_fuse_left = Cfg.breach_fuse
	_changed()


func place_alarm(side: float) -> void:
	alarm_side = side
	_changed()


func set_scope(side: float) -> void:
	if scope_side != side:
		scope_side = side
		_changed()


## The only thing on a door with a hitbox is the trip alarm: one bullet destroys it.
func take_hit(_damage: float, _zone: Hitbox.Zone, _shooter: Node) -> bool:
	if alarm_side != 0.0:
		alarm_side = 0.0
		_changed()
	return false


# --- Replication ---

## Everything a client needs to mirror this door.
func snapshot() -> Dictionary:
	return {state = state, swing = swing_sign, wedged = wedged, charge = charge_side,
			alarm = alarm_side, scope = scope_side}


## Applies the server's snapshot (clients only). The panel swings to match on its own.
func set_from_server(data: Dictionary) -> void:
	state = data.state
	swing_sign = data.swing
	wedged = data.wedged
	charge_side = data.charge
	alarm_side = data.alarm
	scope_side = data.scope
	_show_gadgets()


func target_angle_deg() -> float:
	match state:
		State.CRACKED:
			return swing_sign * Cfg.door_crack_angle_deg
		State.OPEN:
			return swing_sign * Cfg.door_open_angle_deg
	return 0.0


## World-space point on the panel to look at when operating the door.
func panel_point() -> Vector3:
	return to_global(Basis(Vector3.UP, deg_to_rad(angle_deg)) * Vector3(width * 0.5, height * 0.7, 0.0))


func is_settled() -> bool:
	return is_equal_approx(angle_deg, target_angle_deg())


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_run_gadgets(delta)
	if is_settled():
		return
	var next := move_toward(angle_deg, target_angle_deg(), Cfg.door_swing_speed_deg * delta)
	# A body in the way stops the door; it carries on once the path is clear.
	if _panel_would_hit_player(next):
		return
	angle_deg = next
	_panel.rotation_degrees.y = angle_deg


func _run_gadgets(delta: float) -> void:
	# Letting go of a wedged door loses the progress made forcing it.
	if _force_progress > 0.0 and Engine.get_physics_frames() - _last_force_frame > 1:
		_force_progress = 0.0

	if charge_side != 0.0:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			var side := charge_side
			charge_side = 0.0
			wedged = false
			state = State.OPEN
			swing_sign = side  # blown away from the charge
			_changed()
			breached.emit(self, side)

	if alarm_side != 0.0 and _entry_operator_near(side_point(alarm_side, ALARM_INSET, 0.9)):
		alarm_side = 0.0
		_changed()
		alarm_tripped.emit(self)


func _entry_operator_near(point: Vector3) -> bool:
	_alarm_probe.radius = Cfg.alarm_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _alarm_probe
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = Layers.PLAYER
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 4):
		var player := hit.collider as Player
		if player != null and player.team == Team.Id.ENTRY:
			return true
	return false


func _changed() -> void:
	_show_gadgets()
	state_changed.emit(self)


func _show_gadgets() -> void:
	_wedge_visual.visible = wedged
	_wedge_visual.position = Vector3(width * 0.75, 0.035, 0.0)
	_charge_visual.visible = charge_side != 0.0
	_charge_visual.position = Vector3(width * 0.5, 1.1, charge_side * 0.06)
	_scope_visual.visible = scope_side != 0.0
	_scope_visual.position = Vector3(width * 0.5, 0.03, scope_side * 0.15)
	_alarm.visible = alarm_side != 0.0
	_alarm.position = Vector3(width * 0.5, 0.06, alarm_side * ALARM_INSET)
	_alarm_hitbox.set_active(alarm_side != 0.0)


func _next_state(action: Action) -> State:
	if action == Action.TOGGLE_OPEN:
		return State.CLOSED if state == State.OPEN else State.OPEN
	return State.CLOSED if state == State.CRACKED else State.CRACKED


## Doors swing away from whoever operates them. If someone is pressed against the far
## side the door swings toward the operator instead, so a door cannot be held shut by a body.
func _pick_swing_sign(from: Vector3) -> float:
	var away := side_of(from)
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
