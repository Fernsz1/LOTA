extends SceneTree
## Headless unit tests for MoveData (2.2) — frame-data resource.
## Run: godot --headless --script res://tests/test_move_data.gd  (exit 0 = all pass)

const MD := preload("res://scripts/combat/move_data.gd")
const PD := preload("res://scripts/combat/projectile_data.gd")

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
	_test_projectile_spawn_at()
	_test_validate_with_projectile()
	_test_invuln_window()
	_test_velocity_at()
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

func _test_projectile_spawn_at() -> void:
	var m := _jab()                 # startup 3
	_check(m.projectile == null, "no projectile by default")
	_check(m.projectile_spawn_at() == 3, "spawn_at defaults to startup (first active)")
	m.projectile_spawn_frame = 5
	_check(m.projectile_spawn_at() == 5, "explicit projectile_spawn_frame wins")

# A pure-projectile move (no melee hitbox) is valid IFF it has a projectile.
func _test_validate_with_projectile() -> void:
	var m := _jab()
	var empty: Array[Rect2] = []
	m.hitboxes = empty
	_check(not m.validate(), "empty hitboxes + no projectile is invalid")
	m.projectile = PD.new()
	m.projectile.speed = 7.0
	m.projectile.max_range = 900.0
	m.projectile.hitbox = Rect2(0, -12, 28, 24)
	m.projectile.hitstun = 18
	m.projectile.blockstun = 12
	_check(m.validate(), "empty hitboxes + a projectile is valid")

func _test_invuln_window() -> void:
	var m := _jab()
	_check(not m.is_invuln_at(0), "no invuln by default (invuln_startup 0)")
	m.invuln_startup = 5
	_check(m.is_invuln_at(0), "invuln on frame 0 when invuln_startup=5")
	_check(m.is_invuln_at(4), "invuln on frame 4 (last invuln frame)")
	_check(not m.is_invuln_at(5), "no invuln on frame 5 (window is [0,5))")

# 6.3 — self-movement window. Default moves never move; explicit windows are inclusive
# on both edges; -1 end resolves to the last active frame; inverted windows fail validate.
func _test_velocity_at() -> void:
	var m := _jab()                 # move_velocity defaults to 0
	_check(m.velocity_at(0) == 0.0, "velocity_at 0 during startup for a default move")
	_check(m.velocity_at(3) == 0.0, "velocity_at 0 during active for a default move")
	_check(m.velocity_at(4) == 0.0, "velocity_at 0 during recovery for a default move")

	# Dash-kick-shaped move: 10 startup / 6 active / 16 recovery, moves at 11 px/frame.
	var d: Resource = MD.new()
	var boxes: Array[Rect2] = [Rect2(18, -64, 44, 26)]
	d.move_name = "dash_kick"
	d.startup = 10
	d.active = 6
	d.recovery = 16
	d.hitboxes = boxes
	d.hitstun = 20
	d.blockstun = 12
	d.move_velocity = 11.0          # window fields left at defaults (start 0, end -1)
	_check(d.velocity_at(0) == 11.0, "moves on frame 0 (window start default 0)")
	_check(d.velocity_at(15) == 11.0, "moves on frame 15 (last active, -1 end resolves here)")
	_check(d.velocity_at(16) == 0.0, "rooted on frame 16 (first recovery frame)")
	_check(d.validate(), "default velocity window validates")

	# Explicit inclusive window [4, 8].
	d.move_velocity_start = 4
	d.move_velocity_end = 8
	_check(d.velocity_at(3) == 0.0, "no move on frame 3 (before window start)")
	_check(d.velocity_at(4) == 11.0, "moves on frame 4 (window start, inclusive)")
	_check(d.velocity_at(8) == 11.0, "moves on frame 8 (window end, inclusive)")
	_check(d.velocity_at(9) == 0.0, "no move on frame 9 (after window end)")

	# Inverted window is a hard validate() error (only checked when velocity != 0).
	d.move_velocity_start = 8
	d.move_velocity_end = 4
	_check(not d.validate(), "inverted velocity window fails validate()")
