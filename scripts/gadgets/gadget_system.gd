class_name GadgetSystem
extends Node
## The rules for every gadget. The server's copy decides what a gadget request does;
## clients' copies only show the results (grenades in flight, bangs, alarm alerts).

## A trip alarm went off at this door.
signal alarm_raised(door: Door)
## Something went bang here (flashbang or breaching charge).
signal banged(at: Vector3)
## A flashbang was just thrown from here.
signal thrown(at: Vector3)

const BANG_LIGHT_TIME := 0.12

var world: World
var _grenades: Dictionary[int, Flashbang] = {}
var _next_grenade_id := 0


func _init(the_world: World) -> void:
	world = the_world


## Server only: start listening to players and doors.
func serve() -> void:
	for player: Player in world.players.values():
		player.gadget_requested.connect(_on_gadget_requested)
		player.loadout_requested.connect(_on_loadout_requested)
		player.peek_changed.connect(_on_peek_changed)
	for door: Door in world.house.doors.values():
		door.alarm_tripped.connect(_on_alarm_tripped)
		door.breached.connect(_on_breached)
	world.game.phase_changed.connect(_on_phase_changed)


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server():
		for id: int in _grenades:
			_net_grenade.rpc(id, _grenades[id].global_position)


# --- Rules (server) ---

func _on_gadget_requested(player: Player, slot: int, origin: Vector3, direction: Vector3, door: Door) -> void:
	if player.is_dead or slot < 0 or slot >= player.gadgets.size() or player.gadget_charges[slot] == 0:
		return
	var phase := world.game.phase
	var live := phase == Match.Phase.ACTION
	# Suspects may prepare the house during setup; Entry gadgets only work once the round is live.
	var preparing := live or phase == Match.Phase.SETUP
	var side := door.side_of(player.global_position) if door != null else 0.0
	match player.gadgets[slot]:
		"flashbang":
			if not live:
				return
			_throw(origin, direction)
		"breach":
			if not live or door == null or not door.is_shut() or door.charge_side != 0.0:
				return
			door.place_charge(side)
		"wedge":
			if not preparing or door == null or not door.is_shut() or door.wedged:
				return
			door.set_wedged(true)
		"alarm":
			if not preparing or door == null or door.alarm_side != 0.0:
				return
			door.place_alarm(side)
		_:
			return
	player.spend_gadget(slot)


func _on_loadout_requested(player: Player, index: int) -> void:
	if world.game.phase == Match.Phase.SETUP:
		player.set_loadout(index)


## A door shows a lens on the far side from whoever is looking under it.
func _on_peek_changed(_player: Player) -> void:
	for door: Door in world.house.doors.values():
		var side := 0.0
		for player: Player in world.players.values():
			if player.peek_door == door:
				side = -door.side_of(player.global_position)
		door.set_scope(side)


func _on_phase_changed(phase: Match.Phase) -> void:
	# Grenades do not carry over into the next round.
	if phase == Match.Phase.SETUP:
		for id: int in _grenades.keys():
			_remove_grenade(id)
			_net_grenade_gone.rpc(id)


func _throw(origin: Vector3, direction: Vector3) -> void:
	var grenade := _add_grenade(_next_grenade_id)
	_next_grenade_id += 1
	grenade.global_position = origin + direction * 0.4
	grenade.velocity = (direction + Vector3.UP * 0.15).normalized() * Cfg.flash_throw_speed
	grenade.fuse_left = Cfg.flash_fuse
	grenade.detonated.connect(_on_detonated)
	thrown.emit(grenade.global_position)


func _on_detonated(grenade: Flashbang) -> void:
	var at := grenade.global_position
	var id: int = _grenades.find_key(grenade)
	_remove_grenade(id)
	_net_grenade_gone.rpc(id)
	for player: Player in world.players.values():
		var seconds := flash_seconds(player, at + Vector3.UP * 0.1, Cfg.flash_radius, Cfg.flash_duration)
		if seconds > 0.0:
			player.apply_flash(seconds)
	_bang(at)


func _on_breached(door: Door, _charge_side: float) -> void:
	# The blast reaches both sides of the doorway; the panel itself is not in the way.
	for player: Player in world.players.values():
		var from := door.side_point(door.side_of(player.global_position), 0.3, 1.2)
		var seconds := flash_seconds(player, from, Cfg.breach_stun_radius, Cfg.breach_stun_duration)
		if seconds > 0.0:
			player.apply_flash(seconds)
	_bang(door.side_point(0.0, 0.0, 1.2))


func _on_alarm_tripped(door: Door) -> void:
	alarm_raised.emit(door)
	_net_alarm.rpc(door.door_name)


## How long a bang at `from` blinds `player`: nothing without line of sight or beyond `radius`,
## less with distance, and much less when facing away. The hostage is never affected.
func flash_seconds(player: Player, from: Vector3, radius: float, full_duration: float) -> float:
	if player.is_dead:
		return 0.0
	var eyes := player.head.global_position
	var distance := from.distance_to(eyes)
	if distance > radius:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(from, eyes, Layers.WORLD)
	if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return 0.0
	var seconds := full_duration * (1.0 - 0.6 * distance / radius)
	var facing := -player.camera.global_basis.z
	if distance > 0.5 and facing.angle_to(from - eyes) > PI * 0.5:
		seconds *= Cfg.flash_look_away_mult
	return seconds


func _bang(at: Vector3) -> void:
	_show_bang(at)
	_net_bang.rpc(at)


# --- Display (every peer) ---

func _add_grenade(id: int) -> Flashbang:
	var grenade := Flashbang.new()
	grenade.flying = multiplayer.is_server()
	world.add_child(grenade)
	_grenades[id] = grenade
	return grenade


func _remove_grenade(id: int) -> void:
	if _grenades.has(id):
		_grenades[id].queue_free()
		_grenades.erase(id)


func _show_bang(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_energy = 30.0
	light.omni_range = 10.0
	world.add_child(light)
	light.global_position = at
	get_tree().create_timer(BANG_LIGHT_TIME).timeout.connect(light.queue_free)
	banged.emit(at)


# --- Server -> clients ---

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_grenade(id: int, at: Vector3) -> void:
	var is_new := not _grenades.has(id)
	var grenade := _add_grenade(id) if is_new else _grenades[id]
	grenade.global_position = at
	if is_new:
		thrown.emit(at)


@rpc("authority", "call_remote", "reliable")
func _net_grenade_gone(id: int) -> void:
	_remove_grenade(id)


@rpc("authority", "call_remote", "reliable")
func _net_bang(at: Vector3) -> void:
	_show_bang(at)


@rpc("authority", "call_remote", "reliable")
func _net_alarm(door_name: String) -> void:
	alarm_raised.emit(world.house.doors[door_name])
