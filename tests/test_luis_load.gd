extends SceneTree
## Headless load/validate of Luis's bundle (6.2) — the Arnis counter-footsies kit.
## Run: godot --headless --path . --script res://tests/test_luis_load.gd

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
	# mode (see test_rainne_load). The .tres still resolves its script by path.
	var cd: Resource = load("res://characters/luis/luis_data.tres")
	_check(cd != null, "luis_data.tres loads")
	if cd == null:
		print("\n%d checks, %d failures" % [_checks, _failures])
		quit(1)
		return
	_check(cd.character_name == "Luis", "character_name is Luis")
	_check(cd.max_health == 1000, "baseline 1000 health")
	_check(cd.walk_speed > 4.2 and cd.walk_speed < 5.0, "mid walk speed (between Rainne and Jerb)")
	_check(cd.backdash_speed > 7.0 and cd.backdash_frames < 20, "better-than-default backdash (bait tool)")
	for m in [cd.move_fast, cd.move_heavy, cd.move_skill, cd.move_ultimate,
			cd.move_air_fast, cd.move_air_heavy]:
		_check(m != null and m.validate(), "move validates: %s" % (m.move_name if m else "<null>"))

	for m in [cd.move_air_fast, cd.move_air_heavy]:
		_check(not m.is_grab and not m.is_counter, "%s is a plain air strike" % m.move_name)
	_check(not cd.move_fast.is_counter and not cd.move_fast.is_grab, "FAST is a strike")
	_check(cd.move_fast.cancel_window_start >= 0, "FAST is cancelable (footsies confirm)")
	_check(cd.move_heavy.causes_knockdown, "HEAVY knocks down")
	_check(cd.move_skill.is_counter, "SKILL is the counter stance")
	_check(cd.move_skill.hitboxes.is_empty(), "counter stance has no hitboxes")
	_check(cd.move_skill.causes_knockdown, "counter retaliation knocks down")
	_check(cd.move_skill.damage < 180, "counter reward under Jacob's techable grab (180)")
	_check(cd.move_skill.recovery >= 20, "stance recovery is a real punish window")
	_check(cd.move_ultimate.move_velocity > 0.0, "ULT advances (move_velocity)")
	_check(cd.move_ultimate.invuln_startup == 0, "ULT has no invuln (Sofia owns the invuln ult)")
	# The stick outranges every current normal (longest ground pokes in the game).
	_check(cd.move_fast.hitboxes[0].end.x >= 90.0, "FAST reach >= 90px")
	_check(cd.move_heavy.hitboxes[0].end.x >= 105.0, "HEAVY reach >= 105px")
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
