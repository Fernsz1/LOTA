extends SceneTree
## Headless load/validate of Jacob's bundle (6.4) — the Buno grappler.
## Run: godot --headless --path . --script res://tests/test_jacob_load.gd

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
	# mode (see test_rainne_load, which trips on this). The .tres still resolves
	# its script by path, so property access works.
	var cd: Resource = load("res://characters/jacob/jacob_data.tres")
	_check(cd != null, "jacob_data.tres loads")
	_check(cd.character_name == "Jacob", "character_name is Jacob")
	_check(cd.walk_speed < 4.0, "walk_speed slowest on the roster (heavy)")
	_check(cd.gravity > 0.6, "heavy gravity (short jump arc)")
	_check(cd.max_health > 1000, "tanky: more health than the base 1000")
	for m in [cd.move_fast, cd.move_heavy, cd.move_skill, cd.move_ultimate,
			cd.move_air_fast, cd.move_air_heavy]:
		_check(m != null and m.validate(), "move validates: %s" % (m.move_name if m else "<null>"))

	for m in [cd.move_air_fast, cd.move_air_heavy]:
		_check(not m.is_grab and not m.is_counter, "%s is a plain air strike" % m.move_name)
	_check(not cd.move_fast.is_grab and not cd.move_heavy.is_grab, "FAST/HEAVY are strikes")
	_check(cd.move_heavy.causes_knockdown, "HEAVY knocks down")
	_check(cd.move_skill.is_grab, "SKILL is the command grab")
	_check(cd.move_skill.tech_window > 0, "command grab is techable")
	_check(cd.move_ultimate.is_grab, "ULTIMATE is the super grab")
	_check(cd.move_ultimate.tech_window == 0, "super grab is untechable")
	_check(cd.move_ultimate.invuln_startup > 0, "super grab has startup invuln")
	_check(cd.move_ultimate.damage > cd.move_skill.damage, "ultimate out-damages the skill grab")
	# Grabs must be out-ranged by his own strikes (spacing answers him).
	var grab_reach: float = cd.move_skill.hitboxes[0].end.x
	_check(grab_reach <= cd.move_fast.hitboxes[0].end.x, "grab reach <= jab reach")
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
