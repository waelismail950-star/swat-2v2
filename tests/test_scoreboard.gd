extends TestCase


func test_sides_swap_once_after_the_configured_round() -> void:
	var board := Scoreboard.new()
	var entry_by_round: Array[int] = []
	for i in 5:
		entry_by_round.append(board.entry_roster())
		board.next_round()
	check(entry_by_round == [0, 0, 1, 1, 1], "roster 0 is Entry for rounds 1-2, roster 1 after: %s" % [entry_by_round])


func test_wins_are_credited_to_the_roster_playing_that_side() -> void:
	var board := Scoreboard.new()
	board.record_win(Team.Id.ENTRY)      # round 1: roster 0 is Entry
	board.next_round()
	board.record_win(Team.Id.SUSPECTS)   # round 2: roster 1 is Suspects
	board.next_round()
	check(board.scores == [1, 1], "one each before the swap: %s" % [board.scores])
	board.record_win(Team.Id.ENTRY)      # round 3: roster 1 is now Entry
	check(board.scores == [1, 2], "after the swap an Entry win goes to roster 1: %s" % [board.scores])
	check(board.team_of(1) == Team.Id.ENTRY and board.team_of(0) == Team.Id.SUSPECTS, "sides are swapped")


func test_match_ends_at_three_wins() -> void:
	var board := Scoreboard.new()
	board.record_win(Team.Id.ENTRY)
	board.next_round()
	board.record_win(Team.Id.ENTRY)
	board.next_round()
	check(not board.is_match_over(), "2-0 is not over")
	board.record_win(Team.Id.SUSPECTS)   # round 3: roster 0 is Suspects
	check(board.is_match_over(), "3-0 ends the match early")
	check(board.winning_roster() == 0, "roster 0 wins")


func test_match_can_go_to_a_fifth_round() -> void:
	var board := Scoreboard.new()
	for winner: Team.Id in [Team.Id.ENTRY, Team.Id.SUSPECTS, Team.Id.SUSPECTS, Team.Id.ENTRY]:
		board.record_win(winner)
		check(not board.is_match_over(), "not over before round 5")
		board.next_round()
	check(board.scores == [2, 2] and board.round_number == 5, "2-2 going into round 5")
	board.record_win(Team.Id.SUSPECTS)
	check(board.is_match_over() and board.winning_roster() == 0, "decider goes to roster 0")
