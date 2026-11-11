class_name Bot
extends Node
## Simple AI for local test mode. It fills a player's input each tick, exactly as a
## keyboard would. It cheats in one way: Entry bots know which room the hostage is in.
##
## Suspect bots vary from round to round: they pick one of several guard layouts, and may
## shut a door of the hostage room and wedge it, or set a trip alarm inside it, during setup.
## They swing to cover a door when a trip alarm goes off.

const ARRIVE_DISTANCE := 0.35
const AIM_REROLL_TIME := 0.4
const WATCH_SWITCH_TIME := 2.5
const STUCK_TIME := 0.6
const SIDESTEP_TIME := 0.5
## How close to the hostage an Entry bot stands to secure it.
const SECURE_DISTANCE := 1.5
## Where a bot stands, inside the room, to place a gadget on a door: clear of the door's swing.
const GADGET_STANCE := 1.6
const ALERT_TIME := 4.0

var player: Player
var game: Match
var rng := RandomNumberGenerator.new()

var _route: Array[Vector3] = []
var _goal := Vector3.INF
var _seen_for := 0.0
var _aim_error := Vector2.ZERO
var _aim_error_age := INF
var _pulse := false           # alternates each tick to turn a held key into presses
var _stuck_for := 0.0
var _sidestep_left := 0.0
var _sidestep_dir := 1.0
var _last_position := Vector3.ZERO
var _watch_time := 0.0
var _reaction := 0.0
## Gadget jobs for this setup: [{door, slot}]. Rebuilt whenever the hostage room changes.
var _plan: Array[Dictionary] = []
var _plan_room := -1
var _alert_door: Door
var _alert_left := 0.0


func _init(the_player: Player, the_game: Match) -> void:
	player = the_player
	game = the_game
	game.phase_changed.connect(_on_phase_changed)


## A new round teleports the bot, so anything it remembered about where it was going is stale.
func _on_phase_changed(phase: Match.Phase) -> void:
	if phase == Match.Phase.SETUP:
		_route.clear()
		_goal = Vector3.INF
		_seen_for = 0.0
		_sidestep_left = 0.0
		_plan_room = -1
		_alert_left = 0.0


## A trip alarm went off: guards turn to cover that door for a few seconds.
func hear_alarm(door: Door) -> void:
	if player.team == Team.Id.SUSPECTS:
		_alert_door = door
		_alert_left = ALERT_TIME


func think(delta: float) -> void:
	var input := player.input
	input.move = Vector2.ZERO
	input.fire = false
	input.interact = false
	input.gadget_1 = false
	input.gadget_2 = false
	_pulse = not _pulse
	if player.is_dead or game.phase == Match.Phase.WAITING:
		return

	# Blinded, a bot cannot see anyone, but it still fires along the way it was facing.
	if player.flash_left > 0.0 and game.phase == Match.Phase.ACTION:
		if _shot_is_safe():
			input.fire = true if player.arsenal.weapon().stats().auto else _pulse
		return

	var enemy := _visible_enemy() if game.phase == Match.Phase.ACTION else null
	if enemy != null:
		_engage(enemy, delta)
		return
	_seen_for = 0.0
	if player.team == Team.Id.ENTRY:
		_think_entry(delta)
	else:
		_think_suspect(delta)


# --- Roles ---

func _think_entry(delta: float) -> void:
	if game.phase != Match.Phase.ACTION:
		return
	var hostage := game.hostage
	var gap := player.global_position.distance_to(hostage.global_position)
	match hostage.state:
		Hostage.State.HELD:
			if gap > SECURE_DISTANCE:
				_walk_to(hostage.global_position, delta)
			else:
				_turn_toward(hostage.global_position + Vector3.UP * 0.8, delta)
				player.input.interact = player.aimed_interactable() == hostage
		Hostage.State.FOLLOWING:
			# Walk ahead of the hostage to open doors, but never out of escort range.
			if gap > Cfg.hostage_follow_radius - 1.0:
				_walk_to(hostage.global_position, delta)
			else:
				_walk_to(hostage.next_waypoint(), delta)


func _think_suspect(delta: float) -> void:
	var room: Dictionary = House.HOSTAGE_ROOMS[game.hostage_room]
	# Once the hostage is on the move, guarding an empty room is pointless: go after it.
	if game.hostage.state == Hostage.State.FOLLOWING:
		_walk_to(game.hostage.global_position, delta)
		return
	if game.phase == Match.Phase.SETUP and _do_gadget_job(room, delta):
		return
	var posts: Array = room.layouts[game.post_layout]
	var post: Vector3 = posts[game.players_on(player.team).find(player) % posts.size()]
	if not _walk_to(post, delta):
		return
	# At the post: sweep between the room's doorways, unless an alarm says where to look.
	var watching: Vector3
	if _alert_left > 0.0 and _alert_door != null:
		_alert_left -= delta
		watching = _alert_door.side_point(0.0, 0.0, 0.0)
	else:
		var doorways := game.house.entrances(room.room)
		_watch_time += delta
		watching = doorways[int(_watch_time / WATCH_SWITCH_TIME) % doorways.size()]
	_turn_toward(watching + Vector3.UP * 1.4, delta)


## Setup-time job: stand inside the room facing one of its doors, shut it if it is open, and
## place a gadget on it. Returns true while there is still a job to do.
func _do_gadget_job(room: Dictionary, delta: float) -> bool:
	if _plan_room != game.hostage_room:
		_plan_room = game.hostage_room
		_plan = _make_plan(room)
	if _plan.is_empty():
		return false
	var door: Door = _plan[0].door
	var inside := _inside_side(door, room.room)
	if not _walk_to(_stance_for(door, inside, room.room), delta):
		return true
	var off := _turn_toward(door.panel_point(), delta)
	if off > deg_to_rad(3.0) or player.aimed_interactable() != door or not door.is_settled():
		return true
	# A wedge needs a shut door; an alarm does not.
	if _plan[0].slot == player.gadgets.find("wedge") and door.state != Door.State.CLOSED:
		player.input.interact = _pulse
		return true
	if _plan[0].slot == 0:
		player.input.gadget_1 = true
	else:
		player.input.gadget_2 = true
	_plan.pop_front()
	return true


## Which jobs this bot does: the first Suspect wedges a door, the second sets an alarm,
## each only some of the time so rounds differ.
func _make_plan(room: Dictionary) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var doors := game.house.doors_of(room.room)
	if doors.is_empty():
		return plan
	var index := game.players_on(player.team).find(player)
	var wedge := player.gadgets.find("wedge")
	var alarm := player.gadgets.find("alarm")
	if index == 0 and wedge >= 0:
		# A one-door room is sealed by a wedge, so bots do it less often there.
		if rng.randf() < Cfg.bot_wedge_chance * (1.0 if doors.size() > 1 else 0.5):
			plan.append({door = doors[rng.randi() % doors.size()], slot = wedge})
	elif index == 1 and alarm >= 0:
		if rng.randf() < Cfg.bot_alarm_chance:
			plan.append({door = doors[rng.randi() % doors.size()], slot = alarm})
	return plan


## Where to stand to work on `door`. The two guards use different spots, so they never both
## crowd the doorway, and the spot is always on the inside, out of the door's swing.
func _stance_for(door: Door, inside: float, room_name: String) -> Vector3:
	var index := game.players_on(player.team).find(player)
	var lateral := 0.0 if index <= 0 else 0.9
	for sign: float in [-1.0, 1.0]:
		var spot := door.to_global(Vector3(door.width * 0.5 + lateral * sign, 0.0, inside * GADGET_STANCE))
		if lateral == 0.0 or game.house.region_at(spot + Vector3.UP * 0.1) == room_name:
			return spot
	return door.side_point(inside, GADGET_STANCE, 0.0)


## +1 or -1: the side of `door` that is inside `room_name`.
func _inside_side(door: Door, room_name: String) -> float:
	for side: float in [1.0, -1.0]:
		if game.house.region_at(door.side_point(side, 1.0, 0.1)) == room_name:
			return side
	return 1.0


# --- Combat ---

func _visible_enemy() -> Player:
	if player.flash_left > 0.0:
		return null
	var eye := player.camera.global_position
	var facing := -player.global_basis.z
	var nearest: Player = null
	var nearest_distance: float = Cfg.bot_view_range
	for other in game.players:
		if other.team == player.team or other.is_dead:
			continue
		var to := other.head.global_position - eye
		var distance := to.length()
		if distance >= nearest_distance or rad_to_deg(facing.angle_to(to)) > Cfg.bot_fov_deg * 0.5:
			continue
		if _can_see(other.head.global_position) or _can_see(_chest_of(other)):
			nearest = other
			nearest_distance = distance
	return nearest


func _engage(enemy: Player, delta: float) -> void:
	_aim_error_age += delta
	if _aim_error_age > AIM_REROLL_TIME:
		_aim_error_age = 0.0
		var error := deg_to_rad(Cfg.bot_aim_error_deg)
		_aim_error = Vector2(rng.randf_range(-error, error), rng.randf_range(-error, error))
	var aim_at := _chest_of(enemy) if _can_see(_chest_of(enemy)) else enemy.head.global_position
	var off_target := _turn_toward(aim_at, delta, _aim_error)
	if _seen_for == 0.0:
		var to := aim_at - player.camera.global_position
		var already_aimed := rad_to_deg((-player.camera.global_basis.z).angle_to(to)) <= Cfg.bot_preaim_deg
		_reaction = Cfg.bot_preaim_reaction_time if already_aimed else Cfg.bot_reaction_time
	_seen_for += delta
	if _seen_for < _reaction or off_target > deg_to_rad(4.0) or not _shot_is_safe():
		return
	var gun := player.arsenal.weapon()
	player.input.fire = true if gun.stats().auto else _pulse


## False if any part of the weapon's cone would reach the hostage or a teammate first.
func _shot_is_safe() -> bool:
	var view := player.camera.global_basis
	var cone := tan(deg_to_rad(player.arsenal.spread_deg()))
	for offset: Vector2 in [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var direction := (-view.z + (view.x * offset.x + view.y * offset.y) * cone).normalized()
		var hit := Ballistics.cast(player.get_world_3d(), player.camera.global_position,
				direction, player.body.hitbox_rids())
		var hitbox := hit.get("collider") as Hitbox
		if hitbox == null:
			continue
		var target := hitbox.target
		if target is Hostage or (target is Player and (target as Player).team == player.team):
			return false
	return true


func _chest_of(other: Player) -> Vector3:
	return other.global_position + Vector3.UP * other.current_height() * 0.65


func _can_see(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, point, Layers.WORLD)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Movement ---

## Turns toward `point` at the bot's turn rate. Returns the remaining angle in radians.
func _turn_toward(point: Vector3, delta: float, error := Vector2.ZERO) -> float:
	var input := player.input
	var to := point - player.camera.global_position
	var want_yaw := atan2(-to.x, -to.z) + error.x
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length()) + error.y
	var step := deg_to_rad(Cfg.bot_turn_speed_deg) * delta
	input.yaw = rotate_toward(input.yaw, want_yaw, step)
	input.pitch = move_toward(input.pitch, want_pitch, step)
	return maxf(absf(angle_difference(input.yaw, want_yaw)), absf(input.pitch - want_pitch))


## Walks toward `goal`, opening doors on the way. Returns true once there.
func _walk_to(goal: Vector3, delta: float) -> bool:
	if goal.distance_to(_goal) > 0.5:
		_goal = goal
		_route = game.house.route(player.global_position, goal)
	while not _route.is_empty() and _flat_distance(_route[0]) < ARRIVE_DISTANCE:
		_route.pop_front()
	if _route.is_empty():
		return true

	var next := _route[0]
	var off_course := _turn_toward(Vector3(next.x, player.camera.global_position.y, next.z), delta)
	var door := _door_ahead()
	if door != null and door.state != Door.State.OPEN:
		# Face the panel and open it. Never wait for the door to stop moving first: a door
		# that is stopped against this bot's own body would wait for the bot in return.
		_turn_toward(door.panel_point(), delta)
		if player.aimed_interactable() == door:
			# Holding the key forces a wedged door (slow and loud); tapping opens a normal one.
			player.input.interact = true if door.wedged else _pulse
		return false

	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		player.input.move = Vector2(_sidestep_dir, 0.3)
	elif off_course < deg_to_rad(30.0):
		player.input.move = Vector2(0, 1)
		_track_progress(delta)
	return false


func _door_ahead() -> Door:
	var from := player.global_position + Vector3.UP
	var to := from - player.global_basis.z * 1.3
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider.get_parent() as Door if hit else null


## If the bot has been pushing forward without moving, shuffle sideways for a moment.
func _track_progress(delta: float) -> void:
	if player.global_position.distance_to(_last_position) > 1.5 * delta:
		_stuck_for = 0.0
	else:
		_stuck_for += delta
		if _stuck_for > STUCK_TIME:
			_stuck_for = 0.0
			_sidestep_left = SIDESTEP_TIME
			_sidestep_dir = 1.0 if rng.randf() < 0.5 else -1.0
	_last_position = player.global_position


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length()
