extends SceneTree
## Headless load/validate of Sofia's bundle (6.3). Mirrors test_rainne_load.gd.
## Run: godot --headless --path . --script res://tests/test_sofia_load.gd

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
	var cd: CharacterData = load("res://characters/sofia/sofia_data.tres")
	_check(cd != null, "sofia_data.tres loads")
	_check(cd.character_name == "Sofia", "character_name is Sofia")

	# §2 stats — the glass-cannon / mobility profile.
	_check(cd.max_health == 900, "max_health 900 (mobility tax)")
	_check(cd.walk_speed == 5.6, "walk_speed 5.6 (fastest walk)")
	_check(cd.walk_b_speed == 4.6, "walk_b_speed 4.6")
	_check(cd.jump_velocity == -13.5, "jump_velocity -13.5")
	_check(cd.jump_f_speed == 4.3, "jump_f_speed 4.3")
	_check(cd.gravity == 0.63, "gravity 0.63 (falls fast)")
	_check(cd.dash_speed == 11.0 and cd.dash_frames == 14, "dash 11.0/14 (fastest, shortest commit)")
	_check(cd.backdash_speed == 8.5 and cd.backdash_frames == 16, "backdash 8.5/16")

	# All four moves load and validate.
	for m in [cd.move_fast, cd.move_heavy, cd.move_skill, cd.move_ultimate]:
		_check(m != null and m.validate(), "move validates: %s" % (m.move_name if m else "<null>"))

	# Move-specific invariants.
	_check(cd.move_ultimate.invuln_startup == 12, "ultimate invuln_startup 12 (layered reversal)")
	_check(cd.move_skill.move_velocity == 11.0, "dash kick move_velocity 11.0")
	_check(cd.move_ultimate.move_velocity == 13.0, "storm kick move_velocity 13.0")

	# Crouch-coverage rule (§3): every hitbox bottom edge must be below y = -52.
	for m in [cd.move_fast, cd.move_heavy, cd.move_skill, cd.move_ultimate]:
		for h: Rect2 in m.hitboxes:
			var bottom: float = h.position.y + h.size.y
			_check(bottom > -52.0, "%s hitbox bottom %.0f > -52 (hits crouch)" % [m.move_name, bottom])

	# Dash-stat back-compat: Jerb authors nothing → controller-const defaults.
	var jerb: CharacterData = load("res://characters/jerb/jerb_data.tres")
	_check(jerb.dash_speed == 9.0 and jerb.dash_frames == 16, "jerb dash defaults 9.0/16")
	_check(jerb.backdash_speed == 7.0 and jerb.backdash_frames == 20, "jerb backdash defaults 7.0/20")

	# §5.3 health wiring — drive the real controller paths: _apply_character_data()
	# (stat load) then reset_for_round() (the authoritative per-round health seed).
	var box_scene: PackedScene = load("res://scenes/character_box.tscn")

	var sofia_ctrl: Node = box_scene.instantiate()
	sofia_ctrl.character_data = cd
	sofia_ctrl._apply_character_data()
	_check(sofia_ctrl.get_max_health() == 900, "Sofia controller get_max_health() == 900")
	sofia_ctrl.reset_for_round(400.0)
	_check(sofia_ctrl.health == 900, "Sofia round-start health == 900")
	sofia_ctrl.free()

	var jerb_ctrl: Node = box_scene.instantiate()
	jerb_ctrl.character_data = jerb
	jerb_ctrl._apply_character_data()
	_check(jerb_ctrl.get_max_health() == 1000, "Jerb controller get_max_health() == 1000 (back-compat)")
	jerb_ctrl.reset_for_round(880.0)
	_check(jerb_ctrl.health == 1000, "Jerb round-start health == 1000")
	jerb_ctrl.free()

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
