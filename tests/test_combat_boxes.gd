extends SceneTree
## Headless unit tests for CombatBoxes (2.1) — pure AABB box math.
## Run: godot --headless --script res://tests/test_combat_boxes.gd  (exit 0 = all pass)

const CB := preload("res://scripts/combat/combat_boxes.gd")

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
	_test_to_world_facing_right()
	_test_to_world_facing_left()
	_test_to_world_symmetric()
	_test_overlaps_true_false()
	_test_overlaps_empty_early_out()
	_test_edge_touch_not_overlap()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

# facing = 1 simply offsets the local box by origin (no mirroring).
func _test_to_world_facing_right() -> void:
	var w := CB.to_world(Rect2(20, -64, 36, 20), Vector2(100, 500), 1)
	_check(w == Rect2(120, 436, 36, 20), "to_world facing=1 offsets by origin")

# facing = -1 mirrors X (origin.x - pos.x - size.x), never Y.
func _test_to_world_facing_left() -> void:
	var w := CB.to_world(Rect2(20, -64, 36, 20), Vector2(100, 500), -1)
	_check(w == Rect2(44, 436, 36, 20), "to_world facing=-1 mirrors X not Y")

# A box symmetric about x=0 is unchanged by facing.
func _test_to_world_symmetric() -> void:
	var right := CB.to_world(Rect2(-20, -80, 40, 80), Vector2(100, 500), 1)
	var left := CB.to_world(Rect2(-20, -80, 40, 80), Vector2(100, 500), -1)
	_check(right == left, "symmetric box unchanged by facing")

func _test_overlaps_true_false() -> void:
	var a: Array[Rect2] = [Rect2(0, 0, 10, 10)]
	var hit: Array[Rect2] = [Rect2(5, 5, 10, 10)]
	var miss: Array[Rect2] = [Rect2(100, 100, 10, 10)]
	_check(CB.overlaps(a, hit), "overlaps true when rects intersect")
	_check(not CB.overlaps(a, miss), "overlaps false when rects disjoint")

func _test_overlaps_empty_early_out() -> void:
	var some: Array[Rect2] = [Rect2(0, 0, 10, 10)]
	var empty: Array[Rect2] = []
	_check(not CB.overlaps(empty, some), "overlaps([], x) == false (early-out)")
	_check(not CB.overlaps(some, empty), "overlaps(x, []) == false (early-out)")

# Borders excluded: rects sharing only an edge do not count as a hit.
func _test_edge_touch_not_overlap() -> void:
	var a: Array[Rect2] = [Rect2(0, 0, 10, 10)]
	var touch: Array[Rect2] = [Rect2(10, 0, 10, 10)]
	_check(not CB.overlaps(a, touch), "edge-touch is not overlap")
