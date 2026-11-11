class_name Session
extends Node
## Connection, lobby and match start. Listen-server: one player hosts, up to three join.
## Also runs offline for solo play, through exactly the same code.

signal members_changed
signal world_started(world: World)
## The session is over (host left, connection failed). `reason` is for display.
signal ended(reason: String)

const PORT := 24565
const MAX_PLAYERS := 4
const BOT_NAMES: Array[String] = ["Bot Alpha", "Bot Bravo", "Bot Charlie"]

## Peer id -> {name: String, roster: int}. The server's copy is the truth; clients mirror it.
var members: Dictionary = {}
var world: World

var _local_name := "Player"
## Clients that have finished building the world (server only).
var _ready_peers: Array[int] = []


func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: _net_hello.rpc_id(1, _local_name))
	multiplayer.connection_failed.connect(func() -> void: _end("Could not connect."))
	multiplayer.server_disconnected.connect(func() -> void: _end("The host left."))
	multiplayer.peer_disconnected.connect(_on_peer_left)


func is_host() -> bool:
	return multiplayer.is_server()


func in_lobby() -> bool:
	return not members.is_empty() and world == null


func local_roster() -> int:
	return members.get(multiplayer.get_unique_id(), {}).get("roster", 0)


## One human and three bots, no network.
func play_solo(player_name: String) -> void:
	members = {1: {name = player_name, roster = 0}}
	start_match()


func host(player_name: String, port := PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	members = {1: {name = player_name, roster = 0}}
	members_changed.emit()
	return OK


func join(address: String, player_name: String, port := PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	_local_name = player_name
	multiplayer.multiplayer_peer = peer
	return OK


## Drops the connection and the world, back to a clean offline state.
func leave() -> void:
	if world != null:
		world.queue_free()
		world = null
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	members.clear()
	_ready_peers.clear()
	members_changed.emit()


## Asks to move to the other roster. Refused if it is full.
func switch_roster() -> void:
	var wanted := 1 - local_roster()
	if is_host():
		_set_roster(1, wanted)
	else:
		_net_request_roster.rpc_id(1, wanted)


## Host only: fills empty slots with bots and starts the match on every peer.
func start_match() -> void:
	if not is_host() or world != null:
		return
	var participants := []
	var filled := [0, 0]
	var peers := members.keys()
	peers.sort()
	for peer: int in peers:
		var member: Dictionary = members[peer]
		participants.append({id = "P%d" % peer, label = member.name, peer = peer, roster = member.roster, bot = false})
		filled[member.roster] += 1
	var bots := 0
	for roster in 2:
		while filled[roster] < MAX_PLAYERS / 2:
			participants.append({id = "Bot%d" % bots, label = BOT_NAMES[bots], peer = 1, roster = roster, bot = true})
			filled[roster] += 1
			bots += 1
	_net_start.rpc(participants)
	_start_when_everyone_is_ready()


func _set_roster(peer: int, roster: int) -> void:
	if not members.has(peer) or roster < 0 or roster > 1 or world != null:
		return
	var already := members.values().filter(func(m: Dictionary) -> bool: return m.roster == roster).size()
	if already >= MAX_PLAYERS / 2:
		return
	members[peer].roster = roster
	_share_members()


func _share_members() -> void:
	_net_members.rpc(members)
	members_changed.emit()


func _start_when_everyone_is_ready() -> void:
	if world == null or world.game.phase != Match.Phase.WAITING:
		return
	for peer: int in members:
		if peer != 1 and not peer in _ready_peers:
			return
	world.game.start_match()


func _on_peer_left(peer: int) -> void:
	if not is_host() or not members.has(peer):
		return
	members.erase(peer)
	_share_members()
	if world != null:
		world.take_over(peer)
		_start_when_everyone_is_ready()


func _end(reason: String) -> void:
	leave()
	ended.emit(reason)


# --- Client -> server ---

@rpc("any_peer", "call_remote", "reliable")
func _net_hello(player_name: String) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	# Joining is only possible in the lobby.
	if world != null or members.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	var on_zero := members.values().filter(func(m: Dictionary) -> bool: return m.roster == 0).size()
	members[peer] = {name = player_name.left(16), roster = 0 if on_zero * 2 < members.size() else 1}
	_share_members()


@rpc("any_peer", "call_remote", "reliable")
func _net_request_roster(roster: int) -> void:
	if is_host():
		_set_roster(multiplayer.get_remote_sender_id(), roster)


@rpc("any_peer", "call_remote", "reliable")
func _net_ready() -> void:
	if is_host():
		_ready_peers.append(multiplayer.get_remote_sender_id())
		_start_when_everyone_is_ready()


# --- Server -> clients ---

@rpc("authority", "call_remote", "reliable")
func _net_members(list: Dictionary) -> void:
	members = list
	members_changed.emit()


@rpc("authority", "call_local", "reliable")
func _net_start(participants: Array) -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(participants)
	world_started.emit(world)
	if not is_host():
		_net_ready.rpc_id(1)
