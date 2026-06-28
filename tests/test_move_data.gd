extends SceneTree
## Headless unit tests for MoveData (2.2) — frame-data resource.
## Run: godot --headless --script res://tests/test_move_data.gd  (exit 0 = all pass)

const MD := preload("res://scripts/combat/move_data.gd")

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
	_test_total()
	_test_is_active()
	_test_hitboxes_at()
	_test_derived_advantage()
	_test_validate()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

# Build a jab (feel-reference §5–6 light jab): 3 startup / 2 active / 7 recovery.
func _jab() -> Resource:
	var m: Resource = MD.new()
	var boxes: Array[Rect2] = [Rect2(20, -64, 36, 20)]
	m.move_name = "jab"
	m.startup = 3
	m.active = 2
	m.recovery = 7
	m.hitboxes = boxes
	m.damage = 30
	m.hitstun = 13
	m.blockstun = 9
	m.hitstop = 8
	m.pushback_hit = 2.0
	m.pushback_block = 3.0
	return m

func _test_total() -> void:
	_check(_jab().total() == 12, "total() == 3+2+7 == 12")

# frame_in_state is 0-indexed: startup frames are 0..2; first active frame is 3.
func _test_is_active() -> void:
	var m := _jab()
	_check(not m.is_active(2), "is_active(2) false (last startup frame)")
	_check(m.is_active(3), "is_active(3) true (first active frame)")
	_check(m.is_active(4), "is_active(4) true (last active frame)")
	_check(not m.is_active(5), "is_active(5) false (first recovery frame)")

func _test_hitboxes_at() -> void:
	var m := _jab()
	_check(m.hitboxes_at(0).is_empty(), "hitboxes_at(0) empty (startup)")
	_check(m.hitboxes_at(3).size() == 1, "hitboxes_at(3) has 1 box (active)")

# Derived advantage at a first-active-frame contact (feel-reference §3); hitstop ignored.
func _test_derived_advantage() -> void:
	var m := _jab()
	_check(m.on_block() == 1, "on_block() == blockstun-((active-1)+recovery) == 1")
	_check(m.on_hit() == 5, "on_hit() == hitstun-((active-1)+recovery) == 5")

func _test_validate() -> void:
	_check(_jab().validate(), "validate() true for a good move")
	var no_active := _jab()
	no_active.active = 0
	_check(not no_active.validate(), "validate() false when active == 0")
	var no_box := _jab()
	var empty: Array[Rect2] = []
	no_box.hitboxes = empty
	_check(not no_box.validate(), "validate() false when hitboxes empty")
