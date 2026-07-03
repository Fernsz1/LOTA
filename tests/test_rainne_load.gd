extends SceneTree
## Headless load/validate of Rainne's bundle (3.4).
## Run: godot --headless --path . --script res://tests/test_rainne_load.gd

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
	# Untyped: global class_name symbols aren't registered in isolated --script
	# mode; the .tres still resolves its script by path.
	var cd: Resource = load("res://characters/rainne/rainne_data.tres")
	_check(cd != null, "rainne_data.tres loads")
	_check(cd.character_name == "Rainne", "character_name is Rainne")
	_check(cd.walk_speed < 5.0, "walk_speed slower than Jerb (zoner)")
	for m in [cd.move_fast, cd.move_heavy, cd.move_skill, cd.move_ultimate]:
		_check(m != null and m.validate(), "move validates: %s" % (m.move_name if m else "<null>"))
	_check(cd.move_heavy.invuln_startup > 0, "anti-air (HEAVY) has startup invuln")
	_check(cd.move_skill.projectile != null and cd.move_skill.projectile.validate(), "SKILL has a valid projectile")
	_check(cd.move_ultimate.projectile != null and cd.move_ultimate.projectile.validate(), "ULTIMATE has a valid projectile")
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
