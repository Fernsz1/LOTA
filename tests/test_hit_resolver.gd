extends SceneTree
## Headless unit tests for HitResolver (2.4) — the block/hit/none decision.
## Run: godot --headless --script res://tests/test_hit_resolver.gd  (exit 0 = all pass)

const HR := preload("res://scripts/combat/hit_resolver.gd")
const CSM := preload("res://scripts/fsm/character_state_machine.gd")

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
	_test_is_guarding()
	_test_classify()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _test_is_guarding() -> void:
	# Holding back in an actionable ground state guards (stand or crouch block).
	_check(HR.is_guarding(CSM.State.IDLE, true), "IDLE + back → guarding")
	_check(HR.is_guarding(CSM.State.WALK_B, true), "WALK_B + back → guarding (stand-block)")
	_check(HR.is_guarding(CSM.State.CROUCH, true), "CROUCH + back → guarding (crouch-block)")
	# Not holding back → no guard.
	_check(not HR.is_guarding(CSM.State.IDLE, false), "IDLE without back → not guarding")
	# Non-actionable states can't guard even while holding back.
	_check(not HR.is_guarding(CSM.State.FAST_ATTACK, true), "mid-attack → not guarding")
	_check(not HR.is_guarding(CSM.State.JUMP_AIR, true), "airborne → not guarding")
	_check(not HR.is_guarding(CSM.State.HITSTUN, true), "in hitstun → not guarding")

func _test_classify() -> void:
	_check(HR.classify(false, false, false) == HR.Outcome.NONE, "no overlap → NONE")
	_check(HR.classify(true, true, false) == HR.Outcome.NONE, "invulnerable → NONE")
	_check(HR.classify(true, true, true) == HR.Outcome.NONE, "invuln beats guard → NONE")
	_check(HR.classify(true, false, true) == HR.Outcome.BLOCK, "overlap + guarding → BLOCK")
	_check(HR.classify(true, false, false) == HR.Outcome.HIT, "overlap, not guarding → HIT")
