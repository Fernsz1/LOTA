extends Node
## 7.5 — Headless end-to-end run of the modernised training mode: the ORIGINAL
## two-arena layout (P1 + P2 each vs their own dummy across the mid-wall),
## reached through the shared character/stage select flow and dressed with the
## versus MatchHUD. Boots the real training.tscn with a MatchSelection pick
## and asserts: the picks land (humans play their pick, each dummy gets the
## OTHER player's pick), the stage colors apply, the match chrome is trimmed
## (no timer/round/pips), the meter is the REAL rage bar (empty until built or
## refilled with key 5), a cinematic ultimate plays SCOPED to the ulting
## player's half (other pair frozen as bystanders), dummies spawn at their OWN
## max health, and planted dummies never slide from hits.
## Run: godot --headless --path . res://tests/e2e_training_mode.tscn

var _frame: int = 0
var _checks: int = 0
var _failures: int = 0
var _training: Node2D
var _p1: CharacterController
var _p1_dummy: CharacterController
var _p2_dummy: CharacterController
var _p2: CharacterController
var _hud: CanvasLayer
var _dummy_hp_before_hit: int = 0
var _dummy_x_before_hit: float = 0.0


func _ready() -> void:
	var sofia: CharacterData = load("res://characters/sofia/sofia_data.tres")
	var jacob: CharacterData = load("res://characters/jacob/jacob_data.tres")
	var stage: StageData = load("res://stages/dojo/dojo_data.tres")
	MatchSelection.training = true
	MatchSelection.p1_data = sofia
	MatchSelection.p1_color = sofia.color
	MatchSelection.p2_data = jacob
	MatchSelection.p2_color = jacob.color
	MatchSelection.stage_data = stage

	_training = load("res://scenes/training.tscn").instantiate()
	add_child(_training)
	_p1 = _training.get_node("P1")
	_p1_dummy = _training.get_node("P1Dummy")
	_p2_dummy = _training.get_node("P2Dummy")
	_p2 = _training.get_node("P2")
	_hud = _training.get_node("MatchHUD")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		30:
			_check(_hud._name[1].text == "Sofia" and _hud._name[2].text == "Jacob",
					"fighter plates show the two HUMANS' picks (Sofia / Jacob)")
			_check(_p1_dummy.character_data.character_name == "Jacob"
					and _p2_dummy.character_data.character_name == "Sofia",
					"each dummy gets the OTHER player's pick (matchup practice)")
			_check(not _hud._timer.get_parent().visible and not _hud._round.visible,
					"match clock/round chrome hidden in training")
			_check(not _hud._pips[1][0].visible, "round pips hidden in training")
			_check(_training.get_node("Background").color
					== MatchSelection.stage_data.background_color,
					"stage-select pick applied to the training background")
			_check(not _p1.is_ultimate_ready() and not _p2.is_ultimate_ready(),
					"meter is the real rage bar: starts EMPTY (no more pinned-full)")
			_check(_p1_dummy.health == _p1_dummy.get_max_health()
					and _p1_dummy.get_max_health() == 1150,
					"P1's dummy (Jacob) spawns at ITS OWN max health (1150)")

		# --- key 5: instant meter refill for both players ---
		40:
			var ev := InputEventKey.new()
			ev.keycode = KEY_5
			ev.physical_keycode = KEY_5
			ev.pressed = true
			Input.parse_input_event(ev)
		50:
			_check(_p1.is_ultimate_ready() and _p2.is_ultimate_ready(),
					"key 5 refills both players' meters")

		# --- P1 ults: the cutscene plays SCOPED to the LEFT half ---
		60:
			InputManager.set_override(1, InputBuffer.ULTIMATE)
		64:
			InputManager.set_override(1, 0)
		130:
			_check(_p1.is_frozen() and _p1_dummy.is_frozen(),
					"cinematic locks the ulting arena's pair")
			_check(_p2.is_frozen() and _p2_dummy.is_frozen(),
					"the other arena's pair is frozen as bystanders")
			_check(not _hud.visible and not _training.get_node("TrainingHUD").visible,
					"match HUD and training strip hidden mid-cinematic")
			var cam: Camera2D = _training.get_node("Camera")
			_check(cam.position.is_equal_approx(Vector2(640, 360))
					and cam.zoom.is_equal_approx(Vector2.ONE),
					"half-screen mode: the camera never zooms/moves mid-cinematic")
		500:
			var ult: MoveData = _p1.move_ultimate
			_check(_p1_dummy.health == 1150 - ult.damage,
					"dummy took exactly the authored cinematic total (%d)" % ult.damage)
			_check(_p1_dummy.position.x <= 640.0 and _p1.position.x <= 640.0,
					"the whole cutscene stayed inside P1's half of the stage")
			_check(is_equal_approx(_p1_dummy.position.x, 540.0),
					"planted dummy never slid during the cutscene (still at spawn x)")
			_check(not _p1.is_frozen() and not _p2.is_frozen()
					and not _p2_dummy.is_frozen(),
					"everyone released after the cutscene (bystanders too)")
			_check(_hud.visible and _training.get_node("TrainingHUD").visible,
					"match HUD and training strip restored")
			_check(not _p1.is_ultimate_ready(), "P1's meter was spent by the ultimate")

		# --- planted dummy (7.5): a hit damages it but never slides it ---
		520:
			_p1.position.x = _p1_dummy.position.x - 60.0   # into jab range
			_dummy_hp_before_hit = _p1_dummy.health
			_dummy_x_before_hit = _p1_dummy.position.x
		525:
			InputManager.set_override(1, InputBuffer.FAST)
		529:
			InputManager.set_override(1, 0)
		590:
			_check(_p1_dummy.health < _dummy_hp_before_hit, "jab connected on the dummy")
			_check(is_equal_approx(_p1_dummy.position.x, _dummy_x_before_hit),
					"planted dummy did not slide from the hit")
			print("\n%d checks, %d failures" % [_checks, _failures])
			get_tree().quit(1 if _failures > 0 else 0)
		900:
			printerr("FAIL: e2e timed out")
			get_tree().quit(2)
