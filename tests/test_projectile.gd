extends SceneTree
## Headless unit tests for Projectile movement/expiry/hitbox (3.2).
## Run: godot --headless --path . --script res://tests/test_projectile.gd

const PROJ := preload("res://scripts/combat/projectile.gd")
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
	_test_travel_right()
	_test_travel_left()
	_test_expire_at_range()
	_test_hitbox_world_and_empty_when_expired()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _data() -> Resource:
	var p: Resource = PD.new()
	p.speed = 10.0
	p.max_range = 25.0          # expires after 3 steps (10,20,30 -> 30 >= 25)
	p.hitbox = Rect2(0, -10, 20, 20)
	return p

func _make(facing: int) -> Object:
	var proj: Object = PROJ.new()
	proj.setup(_data(), Vector2(100, 200), facing, 1)
	return proj

func _test_travel_right() -> void:
	var proj := _make(1)
	proj.step()
	_check(proj.position.x == 110.0, "facing=1 moves +speed per step")

func _test_travel_left() -> void:
	var proj := _make(-1)
	proj.step()
	_check(proj.position.x == 90.0, "facing=-1 moves -speed per step")

func _test_expire_at_range() -> void:
	var proj := _make(1)
	proj.step(); proj.step()
	_check(not proj.is_expired(), "not expired after 20px travelled (< 25)")
	proj.step()
	_check(proj.is_expired(), "expired once travelled >= max_range")

func _test_hitbox_world_and_empty_when_expired() -> void:
	var proj := _make(1)
	var boxes: Array[Rect2] = proj.get_hitboxes()
	_check(boxes.size() == 1, "get_hitboxes() returns one world box while alive")
	_check(boxes[0] == Rect2(100, 190, 20, 20), "world box = local offset by position, facing=1")
	proj.expire()
	_check(proj.get_hitboxes().is_empty(), "get_hitboxes() empty once expired")
