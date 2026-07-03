extends Node2D
## Throwaway 6.4 dev aid (like fsm_demo for 1.3): auto-drives Jacob's grabs
## end-to-end against Jerb via InputManager overrides and prints CHECK lines.
## Run: godot --headless --path . res://scenes/dev/grab_demo.tscn
## Exits 0 iff all checks pass. Scenarios: takedown connect+slam, tech escape,
## untechable ultimate.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0
const P1_X: float = 500.0
const P2_X: float = 560.0   # dx=60 — inside takedown range (<70)
const PHASE_TIMEOUT: int = 300

@onready var _p1: CharacterController = $P1
@onready var _p2: CharacterController = $P2

var _throw: ThrowSequencer = null
var _phase: int = 0
var _frame: int = 0
var _checks: int = 0
var _failures: int = 0
var _saw_attempt := false
var _saw_grabbed := false
var _saw_release := false
var _saw_knockdown := false
var _saw_tech_exit := false


func _ready() -> void:
	process_physics_priority = 1
	_p1.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, null)
	_p2.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, null)
	InputManager.set_override(1, 0)
	InputManager.set_override(2, 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	print(("PASS: " if cond else "FAIL: ") + msg)
	if not cond:
		_failures += 1


func _physics_process(_delta: float) -> void:
	# Same cross-character ordering as main.gd, minus strikes/projectiles.
	_p1.facing = 1 if _p2.position.x > _p1.position.x else -1
	_p2.facing = 1 if _p1.position.x > _p2.position.x else -1
	if not (_p1.is_frozen() or _p2.is_frozen()):
		if _throw != null:
			if _throw.step():
				_throw = null
		else:
			_throw = ThrowSequencer.try_start(_p1, _p2)

	_record_states()
	_frame += 1
	if _frame > PHASE_TIMEOUT:
		_check(false, "phase %d timed out" % _phase)
		_finish()
		return
	match _phase:
		0: _phase_takedown()
		1: _phase_tech()
		2: _phase_ultimate()
		3: _phase_killing_throw()


func _record_states() -> void:
	var s1: int = _p1.fsm_state()
	var s2: int = _p2.fsm_state()
	_saw_attempt = _saw_attempt or s1 == CharacterStateMachine.State.GRAB_ATTEMPT
	_saw_release = _saw_release or s1 == CharacterStateMachine.State.THROW_RELEASE
	_saw_grabbed = _saw_grabbed or s2 == CharacterStateMachine.State.GRABBED
	_saw_knockdown = _saw_knockdown or s2 == CharacterStateMachine.State.KNOCKDOWN


func _press(player: int, bits: int) -> void:
	# One-frame press: held for the first few frames of a phase, then released.
	InputManager.set_override(player, bits if _frame < 4 else 0)


# Scenario 0 — Buno Takedown connects on an idle Jerb: full slam, damage, knockdown.
func _phase_takedown() -> void:
	_press(1, InputBuffer.SKILL)
	if _saw_knockdown and _p1.fsm_state() == CharacterStateMachine.State.IDLE:
		_check(_saw_attempt, "takedown: attacker entered GRAB_ATTEMPT")
		_check(_saw_grabbed, "takedown: victim was GRABBED")
		_check(_saw_release, "takedown: attacker entered THROW_RELEASE")
		_check(_p2.health == 1000 - 180, "takedown: 180 damage dealt (health=%d)" % _p2.health)
		_next_phase()


# Scenario 1 — victim mashes FAST inside the tech window: clean escape, no damage.
func _phase_tech() -> void:
	_press(1, InputBuffer.SKILL)
	if _p2.fsm_state() == CharacterStateMachine.State.GRABBED:
		InputManager.set_override(2, InputBuffer.FAST)
	if _saw_tech_exit:
		if _p1.fsm_state() == CharacterStateMachine.State.IDLE \
				and _p2.fsm_state() == CharacterStateMachine.State.IDLE:
			_check(_p2.health == 1000, "tech: no damage taken (health=%d)" % _p2.health)
			_check(absf(_p2.position.x - _p1.position.x) > ThrowSequencer.HOLD_OFFSET_X,
				"tech: fighters pushed apart")
			_next_phase()
	elif _saw_grabbed and _p2.fsm_state() == CharacterStateMachine.State.IDLE:
		_saw_tech_exit = true   # GRABBED -> IDLE without a knockdown = the tech fired
		InputManager.set_override(2, 0)
	elif _p2.fsm_state() == CharacterStateMachine.State.KNOCKDOWN:
		_check(false, "tech: victim was slammed despite teching")
		_next_phase()


# Scenario 2 — Earthbreaker is untechable: mashing FAST does not escape.
func _phase_ultimate() -> void:
	_press(1, InputBuffer.ULTIMATE)
	# Victim mashes FAST with alternating frames (rising edges) the whole way.
	InputManager.set_override(2, InputBuffer.FAST if _frame % 2 == 0 else 0)
	if _saw_knockdown:
		_check(_p2.health == 1000 - 300, "ultimate: untechable, 300 damage (health=%d)" % _p2.health)
		_next_phase()


# Scenario 3 — a throw that KILLS: MatchManager forces KO the same frame the
# slam zeroes health, while the victim still has the upward pop velocity. The
# corpse must arc back down and settle on the floor, not float away.
var _ko_forced := false
var _ko_wait := 0

func _phase_killing_throw() -> void:
	# Delay the grab past the tech lookback window: P2's FAST mash from the
	# ultimate scenario is still in its input buffer and would tech instantly.
	InputManager.set_override(1, InputBuffer.SKILL if (_frame >= 30 and _frame < 34) else 0)
	if not _ko_forced:
		if _frame == 1:
			_p2.health = 150   # takedown (180 dmg) will zero this
		if _saw_knockdown and _p2.health <= 0:
			_p2.force_ko()     # what MatchManager does on detecting health <= 0
			_ko_forced = true
		return
	_ko_wait += 1
	if _ko_wait >= 120:
		_check(_p2.fsm_state() == CharacterStateMachine.State.KO, "killing throw: victim stays KO")
		_check(_p2.position.y == FLOOR_Y,
			"killing throw: body settled on the floor (y=%.1f)" % _p2.position.y)
		_finish()


func _next_phase() -> void:
	_phase += 1
	_frame = 0
	_saw_attempt = false
	_saw_grabbed = false
	_saw_release = false
	_saw_knockdown = false
	_throw = null
	InputManager.set_override(1, 0)
	InputManager.set_override(2, 0)
	_p1.reset_for_round(P1_X)
	_p2.reset_for_round(P2_X)


func _finish() -> void:
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
