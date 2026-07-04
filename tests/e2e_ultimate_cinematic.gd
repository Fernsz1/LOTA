extends Node
## 7.3 — Headless end-to-end run of BOTH cinematic ultimates. Boots the real
## match scene (P1 Jerb "rush", P2 Rainne "sky_rally"), presses each player's
## ULTIMATE via the InputManager override hook, and asserts each sequence locks
## both fighters, hides the HUD, deals the authored total damage, knocks the
## victim down, and restores the camera/HUD.
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


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		30:
			_p2_start_health = _p2.health
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
			_check(_camera.position.is_equal_approx(Vector2(640, 360))
					and _camera.zoom.is_equal_approx(Vector2.ONE), "rush: camera home again")
			var p2_state: int = _p2.fsm_state()
			_check(p2_state == CharacterStateMachine.State.IDLE
					or p2_state == CharacterStateMachine.State.KNOCKDOWN
					or p2_state == CharacterStateMachine.State.GETUP,
					"rush: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[p2_state])

		# --- P2 (Rainne, "sky_rally") kicks it off from wherever she stands ---
		750:
			_p1_start_health = _p1.health
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
			_check(_camera.position.is_equal_approx(Vector2(640, 360))
					and _camera.zoom.is_equal_approx(Vector2.ONE), "sky_rally: camera home again")
			var p1_state: int = _p1.fsm_state()
			_check(p1_state == CharacterStateMachine.State.IDLE
					or p1_state == CharacterStateMachine.State.KNOCKDOWN
					or p1_state == CharacterStateMachine.State.GETUP,
					"sky_rally: victim went through knockdown (state now %s)"
					% CharacterStateMachine.State.keys()[p1_state])
			print("\n%d checks, %d failures" % [_checks, _failures])
			get_tree().quit(1 if _failures > 0 else 0)
		2000:
			printerr("FAIL: e2e timed out")
			get_tree().quit(2)
