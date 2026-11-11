class_name Match
extends Node
## Runs a best-of-five: phases, timers, spawns, the hostage and win conditions.
## The server's copy is the single authority on round state; clients' copies only mirror it.

enum Phase { WAITING, SETUP, ACTION, ROUND_END, MATCH_END }
enum Reason {
	EXTRACTED, SUSPECTS_DOWN, HOSTAGE_KILLED_BY_SUSPECTS,   # Entry wins
	ENTRY_DOWN, HOSTAGE_KILLED_BY_ENTRY, TIME_UP,           # Suspects win
}

signal phase_changed(phase: Phase)
## Anything a client needs to mirror has changed (see `snapshot`).
signal changed
signal round_ended(winner: Team.Id, reason: Reason)

const REASON_TEXT: Array[String] = [
	"Hostage extracted", "Both suspects down", "A suspect shot the hostage",
	"Entry team down", "Entry team shot the hostage", "Time ran out",
]

var house: House
var hostage: Hostage
var players: Array[Player] = []
var board := Scoreboard.new()
var phase := Phase.WAITING
var time_left := 0.0
## Index into House.HOSTAGE_ROOMS.
var hostage_room := 0
var last_winner := Team.Id.ENTRY
var last_reason := Reason.TIME_UP
var rng := RandomNumberGenerator.new()


func _init(the_house: House, the_hostage: Hostage) -> void:
	house = the_house
	hostage = the_hostage
	rng.randomize()
	hostage.killed.connect(_on_hostage_killed)
	hostage.extracted.connect(func() -> void: _end_round(Team.Id.ENTRY, Reason.EXTRACTED))
	for spot in house.hostage_spots:
		spot.chosen.connect(func(chosen: HostageSpot, _by: Player) -> void: choose_hostage_room(chosen.index))


## `roster` (0 or 1) is the player's group for the whole match.
func add_player(player: Player, roster: int) -> void:
	player.roster = roster
	player.died.connect(_on_player_died)
	players.append(player)
	hostage.players = players


func start_match() -> void:
	board = Scoreboard.new()
	_start_round()


func players_on(team: Team.Id) -> Array[Player]:
	return players.filter(func(p: Player) -> bool: return p.team == team)


func is_team_down(team: Team.Id) -> bool:
	return players_on(team).all(func(p: Player) -> bool: return p.is_dead)


## Moves the hostage to another candidate room. Only possible during setup.
func choose_hostage_room(index: int) -> void:
	if phase != Phase.SETUP:
		return
	hostage_room = index
	var spot: Vector3 = House.HOSTAGE_ROOMS[index].spot
	hostage.place(spot, house.route(spot, House.EXTRACTION))
	changed.emit()


## Everything a client needs to mirror this match.
func snapshot() -> Dictionary:
	return {phase = phase, time_left = time_left, round_number = board.round_number, scores = board.scores,
			hostage_room = hostage_room, last_winner = last_winner, last_reason = last_reason}


## Applies the server's snapshot (clients only).
func set_from_server(state: Dictionary) -> void:
	time_left = state.time_left
	board.round_number = state.round_number
	board.scores.assign(state.scores)
	hostage_room = state.hostage_room
	last_winner = state.last_winner
	last_reason = state.last_reason
	if phase != state.phase:
		phase = state.phase
		_apply_phase_rules()
		phase_changed.emit(phase)


func _physics_process(delta: float) -> void:
	if phase == Phase.WAITING:
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left > 0.0 or not multiplayer.is_server():
		return
	match phase:
		Phase.SETUP:
			_begin_action()
		Phase.ACTION:
			_end_round(Team.Id.SUSPECTS, Reason.TIME_UP)
		Phase.ROUND_END:
			if board.is_match_over():
				_set_phase(Phase.MATCH_END, Cfg.match_end_time)
			else:
				board.next_round()
				_start_round()
		Phase.MATCH_END:
			start_match()


func _start_round() -> void:
	house.reset_doors(true)
	var placed := [0, 0]  # players spawned so far, per team
	for player in players:
		var team := board.team_of(player.roster)
		var spawns := House.ENTRY_SPAWNS if team == Team.Id.ENTRY else House.SUSPECT_SPAWNS
		var yaw := 0.0 if team == Team.Id.ENTRY else PI  # both sides start facing the front door
		player.assign_team(team)
		player.respawn(Transform3D(Basis(Vector3.UP, yaw), spawns[placed[team] % spawns.size()]))
		placed[team] += 1
	_set_phase(Phase.SETUP, Cfg.setup_time)
	choose_hostage_room(rng.randi_range(0, House.HOSTAGE_ROOMS.size() - 1))


func _begin_action() -> void:
	house.set_exterior_locked(false)
	_set_phase(Phase.ACTION, Cfg.round_time)


func _end_round(winner: Team.Id, reason: Reason) -> void:
	if phase != Phase.ACTION or not multiplayer.is_server():
		return
	last_winner = winner
	last_reason = reason
	board.record_win(winner)
	_set_phase(Phase.ROUND_END, Cfg.round_end_time)
	round_ended.emit(winner, reason)


func _set_phase(new_phase: Phase, duration: float) -> void:
	phase = new_phase
	time_left = duration
	_apply_phase_rules()
	phase_changed.emit(phase)
	changed.emit()


## Rules that follow directly from the phase, applied identically on every peer:
## weapons are live only during the round, hostage markers only during setup.
func _apply_phase_rules() -> void:
	for player in players:
		player.arsenal.safe = phase != Phase.ACTION
	for spot in house.hostage_spots:
		spot.enabled = phase == Phase.SETUP


func _on_player_died(_victim: Player, _killer: Node) -> void:
	if is_team_down(Team.Id.ENTRY):
		_end_round(Team.Id.SUSPECTS, Reason.ENTRY_DOWN)
	elif is_team_down(Team.Id.SUSPECTS):
		_end_round(Team.Id.ENTRY, Reason.SUSPECTS_DOWN)


## Whoever shoots the hostage loses the round, so neither side can use the hostage as a win button.
func _on_hostage_killed(by: Node) -> void:
	if by is Player and (by as Player).team == Team.Id.SUSPECTS:
		_end_round(Team.Id.ENTRY, Reason.HOSTAGE_KILLED_BY_SUSPECTS)
	else:
		_end_round(Team.Id.SUSPECTS, Reason.HOSTAGE_KILLED_BY_ENTRY)
