extends SceneTree
## Headless unit tests for GrabRules (6.4) — who can be grabbed, pure decision.
## Run: godot --headless --script res://tests/test_grab_rules.gd  (exit 0 = pass)

const CSM := preload("res://scripts/fsm/character_state_machine.gd")
const GrabRules := preload("res://scripts/combat/grab_rules.gd")

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
	# Grabbable: grounded neutral, blocking, and attack recovery (whiff punish).
	_check(GrabRules.is_grabbable(CSM.State.IDLE), "IDLE is grabbable")
	_check(GrabRules.is_grabbable(CSM.State.WALK_B), "WALK_B (stand-block) is grabbable — grabs beat block")
	_check(GrabRules.is_grabbable(CSM.State.CROUCH), "CROUCH is grabbable")
	_check(GrabRules.is_grabbable(CSM.State.BLOCK), "BLOCK is grabbable")
	_check(GrabRules.is_grabbable(CSM.State.HEAVY_ATTACK), "HEAVY_ATTACK is grabbable (recovery punish)")
	_check(GrabRules.is_grabbable(CSM.State.DASH), "DASH is grabbable")
	_check(GrabRules.is_grabbable(CSM.State.JUMP_LAND), "JUMP_LAND is grabbable")
	_check(GrabRules.is_grabbable(CSM.State.GRAB_ATTEMPT), "GRAB_ATTEMPT is grabbable (grab race — first resolver wins)")

	# Not grabbable: airborne + prejump (jump escapes grabs).
	_check(not GrabRules.is_grabbable(CSM.State.JUMP_START), "JUMP_START not grabbable (prejump throw-invuln)")
	_check(not GrabRules.is_grabbable(CSM.State.JUMP_AIR), "JUMP_AIR not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.JUMP_F), "JUMP_F not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.JUMP_B), "JUMP_B not grabbable")

	# Not grabbable: reactions, wakeup, KO, already in a throw.
	_check(not GrabRules.is_grabbable(CSM.State.HITSTUN), "HITSTUN not grabbable (no throw loops in combos)")
	_check(not GrabRules.is_grabbable(CSM.State.BLOCKSTUN), "BLOCKSTUN not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.KNOCKDOWN), "KNOCKDOWN not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.GETUP), "GETUP not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.KO), "KO not grabbable")
	_check(not GrabRules.is_grabbable(CSM.State.GRABBED), "GRABBED not grabbable (already held)")
	_check(not GrabRules.is_grabbable(CSM.State.THROW_RELEASE), "THROW_RELEASE not grabbable")

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
