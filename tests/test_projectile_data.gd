extends SceneTree
## Headless unit tests for ProjectileData (3.2).
## Run: godot --headless --path . --script res://tests/test_projectile_data.gd

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
	_test_validate_good()
	_test_validate_bad()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _fireball() -> Resource:
	var p: Resource = PD.new()
	p.projectile_name = "fireball"
	p.speed = 7.0
	p.max_range = 900.0
	p.spawn_offset = Vector2(30, -50)
	p.hitbox = Rect2(0, -12, 28, 24)
	p.damage = 60
	p.hitstun = 18
	p.blockstun = 12
	p.hitstop = 8
	p.pushback_hit = 3.0
	p.pushback_block = 4.0
	return p

func _test_validate_good() -> void:
	_check(_fireball().validate(), "validate() true for a good fireball")

func _test_validate_bad() -> void:
	var no_speed := _fireball()
	no_speed.speed = 0.0
	_check(not no_speed.validate(), "validate() false when speed <= 0")
	var no_range := _fireball()
	no_range.max_range = 0.0
	_check(not no_range.validate(), "validate() false when max_range <= 0")
	var no_box := _fireball()
	no_box.hitbox = Rect2()
	_check(not no_box.validate(), "validate() false when hitbox has zero size")
