extends SceneTree
## Headless load/validate test for the sample jab (2.2). Proves the .tres loads, the
## MoveData schema binds, and the numbers match feel-reference.md (+1 / +5).
## Run: godot --headless --script res://tests/test_sample_move.gd  (exit 0 = all pass)

const JAB := preload("res://characters/jerb/moves/jab.tres")
const HEAVY := preload("res://characters/jerb/moves/heavy.tres")

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
	_check(JAB != null, "jab.tres preloads")
	_check(JAB.validate(), "jab.tres validate() true")
	_check(JAB.total() == 12, "jab total() == 12")
	_check(JAB.on_block() == 1, "jab on_block() == +1 (feel-reference)")
	_check(JAB.on_hit() == 5, "jab on_hit() == +5 (feel-reference)")
	_check(JAB.is_active(3), "jab is_active(3) true")
	_check(JAB.hitboxes_at(3).size() == 1, "jab hitboxes_at(3) has 1 box")
	_check(not JAB.causes_knockdown, "jab does not cause knockdown")

	_check(HEAVY != null, "heavy.tres preloads")
	_check(HEAVY.validate(), "heavy.tres validate() true")
	_check(HEAVY.total() == 33, "heavy total() == 10+4+19 == 33")
	_check(HEAVY.on_block() == -6, "heavy on_block() == -6 (feel-reference §6)")
	_check(HEAVY.causes_knockdown, "heavy causes knockdown (2.5)")
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
