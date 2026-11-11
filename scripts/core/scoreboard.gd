class_name Scoreboard
extends RefCounted
## Score and side assignment for one match. The two groups of players are "rosters"
## 0 and 1; which roster plays which side changes when sides swap.

var scores: Array[int] = [0, 0]
var round_number := 1


## The roster playing Entry this round.
func entry_roster() -> int:
	return 0 if round_number <= Cfg.swap_sides_after_round else 1


func team_of(roster: int) -> Team.Id:
	return Team.Id.ENTRY if roster == entry_roster() else Team.Id.SUSPECTS


func roster_of(team: Team.Id) -> int:
	return entry_roster() if team == Team.Id.ENTRY else 1 - entry_roster()


func record_win(team: Team.Id) -> void:
	scores[roster_of(team)] += 1


func is_match_over() -> bool:
	return maxi(scores[0], scores[1]) >= Cfg.rounds_to_win


## Only meaningful once the match is over.
func winning_roster() -> int:
	return 0 if scores[0] > scores[1] else 1


func next_round() -> void:
	round_number += 1
