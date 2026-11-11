class_name World
extends Node3D
## Everything one match needs: the house, the hostage, the rules and the players.
## Every peer builds an identical copy from the same participant list. The server's copy
## decides what happens; this node carries those decisions to the clients' copies.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var house: House
var hostage: Hostage
var game: Match
var gadgets: GadgetSystem
var sounds: SoundSystem
## Node name -> player.
var players: Dictionary[String, Player] = {}
## The player this machine controls (null on a machine that only runs bots).
var local_player: Player


## `participants` is an Array of {id, label, peer, roster, bot}: `id` becomes the node name,
## `peer` is the network peer that owns the player (1 = the server, which also owns bots).
## Call after this node is in the scene tree.
func build(participants: Array) -> void:
	house = House.new()
	house.name = "House"
	add_child(house)
	hostage = Hostage.new()
	hostage.name = "Hostage"
	add_child(hostage)
	game = Match.new(house, hostage)
	game.name = "Match"
	add_child(game)

	for entry: Dictionary in participants:
		var player: Player = PLAYER_SCENE.instantiate()
		player.name = entry.id
		player.display_name = entry.label
		player.set_multiplayer_authority(entry.peer)
		player.controlled_locally = not entry.bot and entry.peer == multiplayer.get_unique_id()
		add_child(player)
		game.add_player(player, entry.roster)
		players[entry.id] = player
		if player.controlled_locally:
			local_player = player
		if entry.bot and multiplayer.is_server():
			give_brain(player)

	gadgets = GadgetSystem.new(self)
	gadgets.name = "Gadgets"
	add_child(gadgets)
	sounds = SoundSystem.new(self)
	sounds.name = "Sounds"
	add_child(sounds)
	game.phase_changed.connect(_on_phase_changed)
	if multiplayer.is_server():
		gadgets.serve()
		_relay_server_decisions()


## Makes `player` bot-controlled on this machine (which must own it).
func give_brain(player: Player) -> void:
	player.brain = Bot.new(player, game)
	player.add_child(player.brain)


## Server: a peer has left. Their players become bots so the match can go on.
func take_over(peer: int) -> void:
	for id: String in players:
		var player := players[id]
		if player.get_multiplayer_authority() == peer:
			player.set_multiplayer_authority(1)
			give_brain(player)
			_net_take_over.rpc(id)


func _physics_process(_delta: float) -> void:
	if multiplayer.is_server() and game != null and game.phase != Match.Phase.WAITING:
		_net_hostage.rpc(hostage.global_position, hostage.state, hostage.secure_progress)


## Players only start sending their position once the match is running, by which time
## every peer has built its world.
func _on_phase_changed(phase: Match.Phase) -> void:
	for id: String in players:
		players[id].broadcasting = phase != Match.Phase.WAITING


func _relay_server_decisions() -> void:
	for id: String in players:
		var player := players[id]
		player.health_changed.connect(func(p: Player) -> void: _net_health.rpc(id, p.health, p.is_dead))
		player.respawned.connect(func(p: Player) -> void: _net_respawn.rpc(id, p.team, p.global_transform))
		player.arsenal.fired.connect(_on_fired.bind(id))
		player.kit_changed.connect(func(p: Player) -> void: _net_kit.rpc(id, p.loadout_index, p.gadget_charges))
		player.flashed.connect(func(_p: Player, seconds: float) -> void: _net_flashed.rpc(id, seconds))
		player.arsenal.hit_landed.connect(_on_hit_landed.bind(player))
	for door: Door in house.doors.values():
		door.state_changed.connect(func(d: Door) -> void: _net_door.rpc(d.door_name, d.snapshot()))
	house.doors_reset.connect(func(lock: bool) -> void: _net_doors_reset.rpc(lock))
	house.exterior_lock_changed.connect(func(locked: bool) -> void: _net_exterior_locked.rpc(locked))
	game.changed.connect(func() -> void: _net_match.rpc(game.snapshot()))


func _on_fired(_weapon: Weapon, from: Vector3, shots: Array, id: String) -> void:
	var ends := PackedVector3Array()
	var hits := PackedByteArray()
	for shot: Dictionary in shots:
		ends.append(shot.to)
		hits.append(1 if shot.hit else 0)
	_net_shot_fx.rpc(id, from, ends, hits)


## Tells a remote shooter that the server counted their hit.
func _on_hit_landed(zone: Hitbox.Zone, killed: bool, shooter: Player) -> void:
	var owner_peer := shooter.get_multiplayer_authority()
	if owner_peer != multiplayer.get_unique_id():
		_net_hit_marker.rpc_id(owner_peer, zone, killed)


# --- Server -> clients ---
# This node's authority is the server, so "authority" means only the server may send these.

@rpc("authority", "call_remote", "reliable")
func _net_health(id: String, health: float, dead: bool) -> void:
	players[id].set_health_from_server(health, dead)


@rpc("authority", "call_remote", "reliable")
func _net_respawn(id: String, team: Team.Id, at: Transform3D) -> void:
	players[id].assign_team(team)
	players[id].respawn(at)


@rpc("authority", "call_remote", "reliable")
func _net_kit(id: String, loadout_index: int, charges: Array) -> void:
	var player := players[id]
	if player.loadout_index != loadout_index or player.gadgets.is_empty():
		player.set_loadout(loadout_index)
	player.gadget_charges.assign(charges)


@rpc("authority", "call_remote", "reliable")
func _net_flashed(id: String, seconds: float) -> void:
	players[id].flash_left = maxf(players[id].flash_left, seconds)


@rpc("authority", "call_remote", "unreliable")
func _net_shot_fx(id: String, from: Vector3, ends: PackedVector3Array, hits: PackedByteArray) -> void:
	var player := players[id]
	if player.is_multiplayer_authority():
		return  # the shooter's own machine drew this when the trigger was pulled
	var shots := []
	for i in ends.size():
		shots.append({to = ends[i], hit = hits[i] == 1})
	player.show_shots(from, shots)


@rpc("authority", "call_remote", "reliable")
func _net_hit_marker(zone: Hitbox.Zone, killed: bool) -> void:
	if local_player != null:
		local_player.arsenal.hit_landed.emit(zone, killed)


@rpc("authority", "call_remote", "reliable")
func _net_door(door_name: String, snapshot: Dictionary) -> void:
	house.doors[door_name].set_from_server(snapshot)


@rpc("authority", "call_remote", "reliable")
func _net_doors_reset(lock_exterior: bool) -> void:
	house.reset_doors(lock_exterior)


@rpc("authority", "call_remote", "reliable")
func _net_exterior_locked(locked: bool) -> void:
	house.set_exterior_locked(locked)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_hostage(at: Vector3, state: Hostage.State, progress: float) -> void:
	hostage.set_from_server(at, state, progress)


@rpc("authority", "call_remote", "reliable")
func _net_match(state: Dictionary) -> void:
	game.set_from_server(state)


@rpc("authority", "call_remote", "reliable")
func _net_take_over(id: String) -> void:
	players[id].set_multiplayer_authority(1)
