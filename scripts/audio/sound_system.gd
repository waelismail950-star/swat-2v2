class_name SoundSystem
extends Node
## Every sound in a match, and how well the local player hears it.
##
## Each machine makes its own sounds from things it already knows (where players move,
## door states, shots it is shown), so nothing extra crosses the network. A sound reaches
## the listener two ways and the louder one is used:
##   through the air: along the walking route, cut by every door it passes;
##   through the structure: in a straight line, cut once if a wall or floor is in the way.
## A sound that came through doorways is played from the first doorway on the listener's
## side, so it seems to come from that door.

## A sound was made in the world. Fires for every sound, audible or not.
signal emitted(kind: String, at: Vector3)

const VOICES := 16
const EAR_HEIGHT := 1.4
## Your own footsteps are played, but quietly.
const OWN_STEP_LOUDNESS := 0.25
## A player who moves further than this in one tick teleported (respawn); that is not a step.
const TELEPORT_DISTANCE := 1.0

var world: World
var _bank := SoundBank.build()
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice := 0
## Player -> metres walked since their last footstep.
var _walked: Dictionary[Player, float] = {}
var _last_position: Dictionary[Player, Vector3] = {}
## Door -> seconds until its next fuse beep / forcing thump.
var _door_timer: Dictionary[Door, float] = {}


func _init(the_world: World) -> void:
	world = the_world


func _ready() -> void:
	for i in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # distance is handled here
		add_child(voice)
		_voices.append(voice)
	for player: Player in world.players.values():
		player.shots_shown.connect(_on_shots_shown)
	for door: Door in world.house.doors.values():
		door.sounded.connect(func(kind: String) -> void: emit(kind, door.side_point(0.0, 0.0, 1.0)))
	world.gadgets.banged.connect(func(at: Vector3) -> void: emit("bang", at))
	world.gadgets.alarm_raised.connect(func(door: Door) -> void: emit("alarm", door.side_point(0.0, 0.0, 0.3)))
	world.gadgets.thrown.connect(func(at: Vector3) -> void: emit("throw", at))


## Makes a sound at `at`. `by` is the player who made it, if any.
func emit(kind: String, at: Vector3, by: Player = null) -> void:
	emitted.emit(kind, at)
	var ears := _listener_position()
	var heard := {loudness = OWN_STEP_LOUDNESS, from = at, muffled = false} \
			if by != null and by == world.local_player else hearing(kind, at, ears)
	if heard.loudness <= 0.0:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = _bank[kind][1 if heard.muffled else 0]
	voice.volume_db = linear_to_db(heard.loudness * Cfg.master_volume)
	voice.global_position = heard.from
	voice.play()


## How a sound of `kind` made at `source` reaches `ears`:
## {loudness: 0..1, from: where it seems to come from, muffled: bool}.
func hearing(kind: String, source: Vector3, ears: Vector3) -> Dictionary:
	var radius: float = Cfg.noise_radius[kind]
	var straight := source.distance_to(ears)
	var blocked := not _clear(source, ears)
	var direct := maxf(1.0 - straight / radius, 0.0) * (Cfg.sound_wall_mult if blocked else 1.0)
	if not blocked:
		return {loudness = direct, from = source, muffled = false}

	# Through the air: walk the route from the listener to the source, doorway by doorway.
	var route := world.house.route(ears, source)
	var length := 0.0
	var passing := 1.0
	var first_doorway := Vector3.INF
	var at := ears
	for i in route.size():
		# Waypoints are on the floor; sound travels at head height.
		var point := route[i] if i == route.size() - 1 else route[i] + Vector3.UP * EAR_HEIGHT
		length += at.distance_to(point)
		for door: Door in world.house.doors.values():
			if _crosses(door, at, point):
				passing *= _door_factor(door)
				if first_doorway == Vector3.INF:
					first_doorway = door.side_point(0.0, 0.0, EAR_HEIGHT)
		at = point
	var by_air := maxf(1.0 - length / radius, 0.0) * passing if not route.is_empty() else 0.0

	if by_air >= direct:
		return {loudness = by_air, from = first_doorway if first_doorway != Vector3.INF else route[0] + Vector3.UP * EAR_HEIGHT,
				muffled = passing < 1.0}
	return {loudness = direct, from = source, muffled = true}


func _physics_process(delta: float) -> void:
	for player: Player in world.players.values():
		_track_footsteps(player)
	for door: Door in world.house.doors.values():
		_tick_door(door, delta)


## One footstep per stride. How loud depends on how the player is moving, judged from
## what every machine can see: their speed and whether they are crouched.
func _track_footsteps(player: Player) -> void:
	var here := player.global_position
	var moved: Vector3 = here - _last_position.get(player, here)
	_last_position[player] = here
	moved.y = 0.0
	if player.is_dead or moved.length() > TELEPORT_DISTANCE:
		_walked[player] = 0.0
		return
	var speed := moved.length() * Engine.physics_ticks_per_second
	var kind := "step_walk"
	var stride := Cfg.stride_walk
	if player.is_crouching():
		kind = "step_crouch"
		stride = Cfg.stride_crouch
	elif speed > Cfg.walk_speed * Cfg.sprint_step_threshold:
		kind = "step_sprint"
		stride = Cfg.stride_sprint
	_walked[player] = _walked.get(player, 0.0) + moved.length()
	if _walked[player] >= stride:
		_walked[player] = 0.0
		emit(kind, here, player)


## Repeating door sounds: the fuse of a breaching charge, and someone forcing a wedge.
func _tick_door(door: Door, delta: float) -> void:
	var kind := "fuse" if door.charge_side != 0.0 else ("force" if door.forcing else "")
	if kind == "":
		_door_timer.erase(door)
		return
	_door_timer[door] = _door_timer.get(door, 0.0) - delta
	if _door_timer[door] <= 0.0:
		_door_timer[door] = Cfg.fuse_beep_interval if kind == "fuse" else Cfg.force_thump_interval
		emit(kind, door.side_point(0.0, 0.0, 1.0))


func _on_shots_shown(player: Player) -> void:
	emit("shot_" + player.arsenal.weapon().id, player.head.global_position, player)


func _listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


func _clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## True if the straight line from `a` to `b` goes through this door's opening.
func _crosses(door: Door, a: Vector3, b: Vector3) -> bool:
	var from := door.to_local(a)
	var to := door.to_local(b)
	if (from.z >= 0.0) == (to.z >= 0.0):
		return false
	var through := from.lerp(to, from.z / (from.z - to.z))
	return through.x > -0.2 and through.x < door.width + 0.2 and through.y > -0.5 and through.y < door.height + 0.5


func _door_factor(door: Door) -> float:
	match door.state:
		Door.State.CLOSED:
			return Cfg.sound_closed_door_mult
		Door.State.CRACKED:
			return Cfg.sound_cracked_door_mult
	return 1.0
