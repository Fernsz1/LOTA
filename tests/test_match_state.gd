extends SceneTree
## Headless unit tests for MatchState (2.6) — round/match progression.
## Run: godot --headless --script res://tests/test_match_state.gd  (exit 0 = all pass)

const MS := preload("res://scripts/match/match_state.gd")

var _checks := 0
var _failures := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_test_start()
	_test_timer()
	_test_round_progression()
	_test_draw()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _test_start() -> void:
	var m := MS.new()
	m.start_match()
	_check(m.p1_rounds == 0 and m.p2_rounds == 0, "start_match() zeroes rounds")
	_check(m.time_left == MS.ROUND_FRAMES, "start_match() fills the timer")
	_check(m.phase == MS.Phase.FIGHT, "start_match() → FIGHT")
	_check(not m.is_match_over(), "fresh match not over")

func _test_timer() -> void:
	var m := MS.new()
	m.start_match()
	m.tick_timer()
	_check(m.time_left == MS.ROUND_FRAMES - 1, "tick_timer() decrements")
	_check(m.seconds_left() == 99, "seconds_left() rounds up (99)")
	for _i in MS.ROUND_FRAMES:
		m.tick_timer()
	_check(m.time_left == 0, "timer clamps at 0 (never negative)")
	_check(m.time_up(), "time_up() true at 0")

func _test_round_progression() -> void:
	var m := MS.new()
	m.start_match()
	m.record_round_win(1)
	_check(m.p1_rounds == 1, "round 1 → P1 has 1")
	_check(m.phase == MS.Phase.ROUND_END, "first win → ROUND_END")
	_check(not m.is_match_over(), "1 win is not match-over")
	m.start_round()
	_check(m.phase == MS.Phase.FIGHT and m.time_left == MS.ROUND_FRAMES, "start_round() resets")
	m.record_round_win(1)
	_check(m.is_match_over(), "2 wins → match over (best-of-3)")
	_check(m.phase == MS.Phase.MATCH_END, "clinching win → MATCH_END")
	_check(m.match_winner() == 1, "match_winner() == 1")

func _test_draw() -> void:
	var m := MS.new()
	m.start_match()
	m.record_round_win(0)
	_check(m.p1_rounds == 0 and m.p2_rounds == 0, "draw awards no point")
	_check(m.phase == MS.Phase.ROUND_END, "draw → ROUND_END (replay)")
