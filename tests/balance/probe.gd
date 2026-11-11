extends Node
## Balance probe: bots play many rounds under different Entry tactics and the win rates
## are printed. Not a pass/fail test. Run with:
##   godot --headless --fixed-fps 60 res://tests/balance/probe.tscn
## Add `-- --trials=N` to change rounds per room per tactic (default 8).
##
## Tactics, always against two guard bots in the hostage room:
##   solo        one Entry bot goes in alone
##   pair        two Entry bots go in together
##   pair+flash  as pair, and the guards are blinded as the first bot reaches the room,
##               standing in for a well-thrown flashbang (bots cannot throw one)

const TACTICS: Array[String] = ["solo", "pair", "pair+flash"]
## How close the first Entry bot gets to a doorway of the hostage room before the flash.
const FLASH_TRIGGER_DISTANCE := 1.6
const ROUND_LIMIT := 120.0


func _ready() -> void:
	var trials := 8
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trials="):
			trials = int(argument.trim_prefix("--trials="))
	Cfg.setup_time = 20.0   # long enough for the guards to place gadgets and reach their posts
	Cfg.round_time = ROUND_LIMIT
	Cfg.round_end_time = 0.1

	print("Entry win rate over %d rounds per room (hostage room down, tactic across)" % trials)
	print("%-10s %s" % ["", "  ".join(TACTICS.map(func(t: String) -> String: return "%-12s" % t))])
	var totals := {}
	for room in House.HOSTAGE_ROOMS.size():
		var cells: Array[String] = []
		for tactic in TACTICS:
			var wins := 0
			for trial in trials:
				if await _play_round(room, tactic):
					wins += 1
			totals[tactic] = totals.get(tactic, 0) + wins
			cells.append("%-12s" % ("%d%%" % roundi(100.0 * wins / trials)))
		print("%-10s %s" % [House.HOSTAGE_ROOMS[room].room, "  ".join(cells)])
	var summary: Array[String] = []
	for tactic in TACTICS:
		summary.append("%-12s" % ("%d%%" % roundi(100.0 * totals[tactic] / (trials * House.HOSTAGE_ROOMS.size()))))
	print("%-10s %s" % ["ALL", "  ".join(summary)])
	get_tree().quit()


## Plays one round in a fresh world. Returns true if Entry won.
func _play_round(room: int, tactic: String) -> bool:
	var world := World.new()
	add_child(world)
	var participants := []
	for i in (1 if tactic == "solo" else 2):
		participants.append({id = "E%d" % i, label = "E%d" % i, peer = 1, roster = 0, bot = true})
	for i in 2:
		participants.append({id = "S%d" % i, label = "S%d" % i, peer = 1, roster = 1, bot = true})
	world.build(participants)
	for player: Player in world.players.values():
		player.brain.rng.randomize()
		player.arsenal.rng.randomize()

	var result := {}
	world.game.round_ended.connect(func(winner: Team.Id, _reason: Match.Reason) -> void: result.winner = winner)
	world.game.start_match()
	world.game.choose_hostage_room(room)
	var flashed := tactic != "pair+flash"
	while result.is_empty():
		await get_tree().physics_frame
		if not flashed and world.game.phase == Match.Phase.ACTION and _entry_at_the_room(world, room):
			flashed = true
			for guard in world.game.players_on(Team.Id.SUSPECTS):
				guard.apply_flash(Cfg.flash_duration * 0.7)
	world.queue_free()
	await get_tree().physics_frame
	return result.winner == Team.Id.ENTRY


func _entry_at_the_room(world: World, room: int) -> bool:
	for doorway: Vector3 in world.house.entrances(House.HOSTAGE_ROOMS[room].room):
		for operator in world.game.players_on(Team.Id.ENTRY):
			if not operator.is_dead and operator.global_position.distance_to(doorway) < FLASH_TRIGGER_DISTANCE:
				return true
	return false
