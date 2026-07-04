extends Node
## 7.3 — Headless end-to-end run of ALL cinematic ultimates. Boots the real
## match scene (P1 Jerb "rush", P2 Rainne "sky_rally", then P1 is swapped to
## Jacob for "slam", Luis for "weave", and Sofia for "blitz"), presses each
## player's ULTIMATE via the InputManager override hook, and asserts each
## sequence locks both fighters, hides the HUD, deals the authored total
## damage, knocks the victim down, and restores the camera/HUD.
## Run: godot --headless --path . res://tests/e2e_ultimate_cinematic.tscn
## (Unlike the tests/*.gd SceneTree scripts, this needs the autoloads, so it
## runs as a scene inside the normal game boot.)

var _frame: int = 0
var _checks: int = 0
var _failures: int = 0
var _main: Node2D
var _p1: CharacterController
var _p2: CharacterController
var _hud: CanvasLayer
var _camera: Camera2D
var _p2_start_health: int = 0
var _p1_start_health: int = 0


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_p1 = _main.get_node("P1")
	_p2 = _main.get_node("P2")
	_hud = _main.get_node("MatchHUD")
	_camera = _main.get_node("Camera")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)


## After a cutscene the camera hands back to the dynamic fight camera, which
## frames both fighters (zoom 1.0..CAM_MAX_ZOOM, view inside the canvas) —
## it no longer parks at the identity view, so assert the framing instead.
func _match_framing() -> bool:
	var z: float = _camera.zoom.x
	if z < 0.99 or z > 2.2:
		return false
	var half_w: float = 640.0 / z
	var half_h: float = 360.0 / z
	return _camera.position.x >= half_w - 1.0 \
			and _camera.position.x <= 1280.0 - half_w + 1.0 \
			and _camera.position.y >= half_h - 1.0 \
			and _camera.position.y <= 720.0 - half_h + 1.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		30:
			_p2_start_health = _p2.health
			_p1.fill_meter()   # ultimates are meter-gated (spec 2026-07-04)
			InputManager.set_override(1, InputBuffer.ULTIMATE)
		34:
			InputManager.set_override(1, 0)
		100:
			_check(_p1.is_frozen() and _p2.is_frozen(), "both fighters locked mid-cinematic")
			_check(not _hud.visible, "HUD hidden mid-cinematic")
			_check(_camera.zoom.x > 1.5, "camera zoomed in")
		200:
			_check(_p2.health < _p2_start_health, "victim took scripted damage mid-sequence")
		700:
			var ult: MoveData = _p1.move_ultimate
			_check(_p2.health == _p2_start_health - ult.damage,
					"rush: victim took exactly the authored total (%d): %d -> %d"
					% [ult.damage, _p2_start_health, _p2.health])
			_check(not _p1.is_frozen() and not _p2.is_frozen(), "rush: both fighters released")
			_check(_hud.visible, "rush: HUD restored")
			_check(_match_framing(), "rush: camera back to match framing")
			var p2_state: int = _p2.fsm_state()
			_check(p2_state == CharacterStateMachine.State.IDLE
					or p2_state == CharacterStateMachine.State.KNOCKDOWN
					or p2_state == CharacterStateMachine.State.GETUP,
					"rush: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[p2_state])

		# --- P2 (Rainne, "sky_rally") kicks it off from wherever she stands ---
		750:
			_p1_start_health = _p1.health
			_p2.fill_meter()
			InputManager.set_override(2, InputBuffer.ULTIMATE)
		754:
			InputManager.set_override(2, 0)
		820:
			_check(_p1.is_frozen() and _p2.is_frozen(), "sky_rally: both fighters locked")
			_check(not _hud.visible, "sky_rally: HUD hidden")
		1450:
			var ult2: MoveData = _p2.move_ultimate
			_check(ult2.cinematic_style == "sky_rally", "P2 ultimate is Rainne's sky_rally")
			_check(_p1.health == _p1_start_health - ult2.damage,
					"sky_rally: victim took exactly the authored total (%d): %d -> %d"
					% [ult2.damage, _p1_start_health, _p1.health])
			_check(not _p1.is_frozen() and not _p2.is_frozen(), "sky_rally: both fighters released")
			_check(_hud.visible, "sky_rally: HUD restored")
			_check(_match_framing(), "sky_rally: camera back to match framing")
			var p1_state: int = _p1.fsm_state()
			_check(p1_state == CharacterStateMachine.State.IDLE
					or p1_state == CharacterStateMachine.State.KNOCKDOWN
					or p1_state == CharacterStateMachine.State.GETUP,
					"sky_rally: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[p1_state])

		# --- P1 swapped to Jacob ("slam"): a grab ultimate must also trigger ---
		1500:
			var jd: CharacterData = load("res://characters/jacob/jacob_data.tres")
			_p1.set_character(jd, jd.color)
			_p2_start_health = _p2.health
		1510:
			_p1.fill_meter()
			InputManager.set_override(1, InputBuffer.ULTIMATE)
		1514:
			InputManager.set_override(1, 0)
		1580:
			_check(_p1.is_frozen() and _p2.is_frozen(), "slam: both fighters locked")
			_check(not _hud.visible, "slam: HUD hidden")
		2200:
			var ult3: MoveData = _p1.move_ultimate
			_check(ult3.cinematic_style == "slam" and ult3.is_grab,
					"P1 ultimate is Jacob's slam (a grab)")
			_check(_p2.health == _p2_start_health - ult3.damage,
					"slam: victim took exactly the authored total (%d): %d -> %d"
					% [ult3.damage, _p2_start_health, _p2.health])
			_check(not _p1.is_frozen() and not _p2.is_frozen(), "slam: both fighters released")
			_check(_hud.visible, "slam: HUD restored")
			_check(_match_framing(), "slam: camera back to match framing")
			var vic_state: int = _p2.fsm_state()
			_check(vic_state == CharacterStateMachine.State.IDLE
					or vic_state == CharacterStateMachine.State.KNOCKDOWN
					or vic_state == CharacterStateMachine.State.GETUP,
					"slam: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[vic_state])
			var p2_box: ColorRect = _p2.get_node("Box")
			_check(is_zero_approx(p2_box.rotation), "slam: victim box rotation restored")

		# --- P1 swapped to Luis ("weave"): the advancing stick flurry ---
		2250:
			var ld: CharacterData = load("res://characters/luis/luis_data.tres")
			_p1.set_character(ld, ld.color)
			_p2_start_health = _p2.health
		2260:
			_p1.fill_meter()
			InputManager.set_override(1, InputBuffer.ULTIMATE)
		2264:
			InputManager.set_override(1, 0)
		2330:
			_check(_p1.is_frozen() and _p2.is_frozen(), "weave: both fighters locked")
			_check(not _hud.visible, "weave: HUD hidden")
		3000:
			var ult4: MoveData = _p1.move_ultimate
			_check(ult4.cinematic_style == "weave", "P1 ultimate is Luis's weave")
			_check(_p2.health == _p2_start_health - ult4.damage,
					"weave: victim took exactly the authored total (%d): %d -> %d"
					% [ult4.damage, _p2_start_health, _p2.health])
			_check(not _p1.is_frozen() and not _p2.is_frozen(), "weave: both fighters released")
			_check(_hud.visible, "weave: HUD restored")
			_check(_match_framing(), "weave: camera back to match framing")
			var weave_vic: int = _p2.fsm_state()
			_check(weave_vic == CharacterStateMachine.State.IDLE
					or weave_vic == CharacterStateMachine.State.KNOCKDOWN
					or weave_vic == CharacterStateMachine.State.GETUP,
					"weave: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[weave_vic])

		# --- P1 swapped to Sofia ("blitz"): the side-switching kick barrage ---
		3050:
			var sd: CharacterData = load("res://characters/sofia/sofia_data.tres")
			_p1.set_character(sd, sd.color)
			_p2_start_health = _p2.health
		3060:
			_p1.fill_meter()
			InputManager.set_override(1, InputBuffer.ULTIMATE)
		3064:
			InputManager.set_override(1, 0)
		3130:
			_check(_p1.is_frozen() and _p2.is_frozen(), "blitz: both fighters locked")
			_check(not _hud.visible, "blitz: HUD hidden")
		3800:
			var ult5: MoveData = _p1.move_ultimate
			_check(ult5.cinematic_style == "blitz", "P1 ultimate is Sofia's blitz")
			_check(_p2.health == _p2_start_health - ult5.damage,
					"blitz: victim took exactly the authored total (%d): %d -> %d"
					% [ult5.damage, _p2_start_health, _p2.health])
			_check(not _p1.is_frozen() and not _p2.is_frozen(), "blitz: both fighters released")
			_check(_hud.visible, "blitz: HUD restored")
			_check(_match_framing(), "blitz: camera back to match framing")
			var blitz_vic: int = _p2.fsm_state()
			_check(blitz_vic == CharacterStateMachine.State.IDLE
					or blitz_vic == CharacterStateMachine.State.KNOCKDOWN
					or blitz_vic == CharacterStateMachine.State.GETUP,
					"blitz: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[blitz_vic])
			var p1_box: ColorRect = _p1.get_node("Box")
			_check(is_zero_approx(p1_box.rotation), "blitz: attacker box rotation restored")
			print("\n%d checks, %d failures" % [_checks, _failures])
			get_tree().quit(1 if _failures > 0 else 0)
		4200:
			printerr("FAIL: e2e timed out")
			get_tree().quit(2)
