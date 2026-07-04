extends SceneTree
## Headless unit tests for CharacterStateMachine.
## Run: godot --headless --script res://tests/test_fsm.gd  (exit 0 = all pass)

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
	_test_initial()
	_test_categories()
	_test_actionable_exits()
	_test_air_ground_boundary()
	_test_busy_only_exit()
	_test_knockdown_path()
	_test_force_reactions()
	_test_ko_terminal()
	_test_same_state_request()
	_test_frame_counter()
	_test_convenience_wrappers()
	_test_grab_states()
	_test_air_attack_states()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _name(s: int) -> String:
	return CSM.State.keys()[s]

func _test_initial() -> void:
	var sm := CSM.new()
	_check(sm.state == CSM.State.IDLE, "starts in IDLE")
	_check(sm.frame_in_state == 0, "starts at frame 0")
	_check(sm.prev_state == CSM.State.IDLE, "prev_state starts IDLE")

func _test_categories() -> void:
	_check(CSM.is_airborne(CSM.State.JUMP_AIR), "JUMP_AIR is airborne")
	_check(CSM.is_airborne(CSM.State.JUMP_F), "JUMP_F is airborne")
	_check(not CSM.is_airborne(CSM.State.IDLE), "IDLE is not airborne")
	_check(CSM.is_grounded(CSM.State.IDLE), "IDLE is grounded")
	_check(CSM.is_actionable(CSM.State.BLOCK), "BLOCK is actionable")
	_check(not CSM.is_actionable(CSM.State.DASH), "DASH is not actionable")
	_check(CSM.is_attacking(CSM.State.HEAVY_ATTACK), "HEAVY_ATTACK is attacking")
	_check(CSM.is_busy(CSM.State.DASH), "DASH is busy")
	_check(CSM.is_busy(CSM.State.FAST_ATTACK), "FAST_ATTACK is busy")
	_check(CSM.is_in_reaction(CSM.State.HITSTUN), "HITSTUN is reaction")
	_check(CSM.is_ko(CSM.State.KO), "KO is ko")

func _test_actionable_exits() -> void:
	var sm := CSM.new()
	_check(sm.request(CSM.State.WALK_F), "IDLE -> WALK_F allowed")
	_check(sm.state == CSM.State.WALK_F, "now in WALK_F")
	_check(sm.request(CSM.State.CROUCH), "WALK_F -> CROUCH allowed")
	_check(sm.request(CSM.State.FAST_ATTACK), "CROUCH -> FAST_ATTACK allowed")
	_check(sm.request(CSM.State.IDLE), "FAST_ATTACK -> IDLE allowed (recovery)")
	_check(sm.request(CSM.State.BLOCK), "IDLE -> BLOCK allowed")

func _test_air_ground_boundary() -> void:
	var sm := CSM.new()
	_check(not sm.request(CSM.State.JUMP_AIR), "IDLE -> JUMP_AIR rejected (must prejump)")
	_check(sm.state == CSM.State.IDLE, "state unchanged after rejected request")
	_check(sm.request(CSM.State.JUMP_START), "IDLE -> JUMP_START allowed")
	_check(sm.request(CSM.State.JUMP_AIR), "JUMP_START -> JUMP_AIR allowed")
	_check(not sm.request(CSM.State.IDLE), "JUMP_AIR -> IDLE rejected (must land)")
	_check(sm.request(CSM.State.JUMP_LAND), "JUMP_AIR -> JUMP_LAND allowed")
	_check(sm.request(CSM.State.IDLE), "JUMP_LAND -> IDLE allowed")

func _test_busy_only_exit() -> void:
	var sm := CSM.new()
	_check(sm.request(CSM.State.DASH), "IDLE -> DASH allowed")
	_check(not sm.request(CSM.State.HEAVY_ATTACK), "DASH -> HEAVY_ATTACK rejected (no cancel in 1.3)")
	_check(sm.request(CSM.State.IDLE), "DASH -> IDLE allowed (resolves)")

func _test_knockdown_path() -> void:
	var sm := CSM.new()
	sm.force(CSM.State.KNOCKDOWN)
	_check(sm.state == CSM.State.KNOCKDOWN, "forced into KNOCKDOWN")
	_check(not sm.request(CSM.State.IDLE), "KNOCKDOWN -> IDLE rejected (must get up)")
	_check(sm.request(CSM.State.GETUP), "KNOCKDOWN -> GETUP allowed")
	_check(sm.request(CSM.State.IDLE), "GETUP -> IDLE allowed")

func _test_force_reactions() -> void:
	var sm := CSM.new()
	sm.request(CSM.State.HEAVY_ATTACK)
	sm.force(CSM.State.HITSTUN)
	_check(sm.state == CSM.State.HITSTUN, "force(HITSTUN) interrupts an attack")
	_check(sm.request(CSM.State.IDLE), "HITSTUN -> IDLE allowed (stun ends)")
	sm.request(CSM.State.JUMP_START)
	sm.request(CSM.State.JUMP_AIR)
	sm.force(CSM.State.KNOCKDOWN)
	_check(sm.state == CSM.State.KNOCKDOWN, "force(KNOCKDOWN) works from airborne")

func _test_ko_terminal() -> void:
	var sm := CSM.new()
	sm.force(CSM.State.KO)
	_check(sm.state == CSM.State.KO, "forced into KO")
	_check(not sm.request(CSM.State.IDLE), "KO -> IDLE rejected via request")
	_check(not sm.can_transition(CSM.State.GETUP), "KO can_transition() is false for all")
	sm.reset()
	_check(sm.state == CSM.State.IDLE, "reset() escapes KO to IDLE")

func _test_same_state_request() -> void:
	var sm := CSM.new()
	sm.tick(); sm.tick(); sm.tick()
	var f := sm.frame_in_state
	_check(sm.request(CSM.State.IDLE), "re-request current state returns true")
	_check(sm.frame_in_state == f, "re-request current state does NOT reset frame_in_state")

func _test_frame_counter() -> void:
	var sm := CSM.new()
	_check(sm.frame_in_state == 0, "entry frame reads 0")
	sm.tick()
	_check(sm.frame_in_state == 1, "first tick on initial state -> 1")
	sm.tick()
	_check(sm.frame_in_state == 2, "second tick -> 2")
	_check(sm.request(CSM.State.WALK_F), "transition to WALK_F")
	_check(sm.frame_in_state == 0, "transition resets frame_in_state to 0")
	sm.tick()
	_check(sm.frame_in_state == 0, "first tick after a change is absorbed (entry frame kept at 0)")
	sm.tick()
	_check(sm.frame_in_state == 1, "next tick -> 1")
	_check(sm.prev_state == CSM.State.IDLE, "prev_state tracks the previous state")

# 6.4 — grab states (GRAB_ATTEMPT / GRABBED / THROW_RELEASE), per the design in
# docs/superpowers/specs/2026-07-03-jacob-grappler-design.md.
func _test_grab_states() -> void:
	# categories
	_check(CSM.is_busy(CSM.State.GRAB_ATTEMPT), "GRAB_ATTEMPT is busy")
	_check(CSM.is_busy(CSM.State.THROW_RELEASE), "THROW_RELEASE is busy")
	_check(CSM.is_in_reaction(CSM.State.GRABBED), "GRABBED is reaction")
	_check(not CSM.is_attacking(CSM.State.GRAB_ATTEMPT), "GRAB_ATTEMPT is NOT attacking (no strike hitboxes)")
	_check(not CSM.is_actionable(CSM.State.GRABBED), "GRABBED is not actionable")
	_check(CSM.is_grounded(CSM.State.GRAB_ATTEMPT), "GRAB_ATTEMPT is grounded")

	# attacker path: actionable -> GRAB_ATTEMPT -> THROW_RELEASE (connect) -> IDLE
	var sm := CSM.new()
	_check(sm.request(CSM.State.GRAB_ATTEMPT), "IDLE -> GRAB_ATTEMPT allowed")
	_check(not sm.request(CSM.State.FAST_ATTACK), "GRAB_ATTEMPT -> FAST_ATTACK rejected (busy)")
	_check(sm.request(CSM.State.THROW_RELEASE), "GRAB_ATTEMPT -> THROW_RELEASE allowed (connect)")
	_check(not sm.request(CSM.State.GRAB_ATTEMPT), "THROW_RELEASE -> GRAB_ATTEMPT rejected")
	_check(sm.request(CSM.State.IDLE), "THROW_RELEASE -> IDLE allowed (release)")

	# attacker whiff path: GRAB_ATTEMPT -> IDLE
	sm = CSM.new()
	sm.request(CSM.State.WALK_F)
	_check(sm.request(CSM.State.GRAB_ATTEMPT), "WALK_F -> GRAB_ATTEMPT allowed")
	_check(sm.request(CSM.State.IDLE), "GRAB_ATTEMPT -> IDLE allowed (whiff)")

	# victim path: forced GRABBED; tech exits to IDLE; throw forces KNOCKDOWN
	sm = CSM.new()
	sm.request(CSM.State.HEAVY_ATTACK)              # grabbed out of recovery
	sm.force(CSM.State.GRABBED)
	_check(sm.state == CSM.State.GRABBED, "force(GRABBED) interrupts an attack")
	_check(not sm.request(CSM.State.WALK_F), "GRABBED -> WALK_F rejected (held)")
	_check(sm.request(CSM.State.IDLE), "GRABBED -> IDLE allowed (tech/abort)")
	sm.force(CSM.State.GRABBED)
	sm.force(CSM.State.KNOCKDOWN)
	_check(sm.state == CSM.State.KNOCKDOWN, "GRABBED -> forced KNOCKDOWN (throw lands)")

	# interrupt: the thrower can still be forced into reactions / KO
	sm = CSM.new()
	sm.request(CSM.State.GRAB_ATTEMPT)
	sm.request(CSM.State.THROW_RELEASE)
	sm.force(CSM.State.HITSTUN)
	_check(sm.state == CSM.State.HITSTUN, "THROW_RELEASE interrupted by force(HITSTUN)")

	# airborne cannot request a grab
	sm = CSM.new()
	sm.request(CSM.State.JUMP_START)
	sm.request(CSM.State.JUMP_AIR)
	_check(not sm.request(CSM.State.GRAB_ATTEMPT), "JUMP_AIR -> GRAB_ATTEMPT rejected (grabs are grounded)")


func _test_air_attack_states() -> void:
	# Entry: only from the three airborne jump states.
	var sm := CSM.new()
	_check(not sm.request(CSM.State.AIR_FAST_ATTACK), "IDLE -> AIR_FAST_ATTACK rejected")
	_check(not sm.request(CSM.State.AIR_HEAVY_ATTACK), "IDLE -> AIR_HEAVY_ATTACK rejected")
	sm.request(CSM.State.JUMP_START)
	_check(not sm.request(CSM.State.AIR_FAST_ATTACK), "JUMP_START -> AIR_FAST_ATTACK rejected (prejump)")
	sm.request(CSM.State.JUMP_AIR)
	_check(sm.request(CSM.State.AIR_FAST_ATTACK), "JUMP_AIR -> AIR_FAST_ATTACK allowed")
	# Exits: finished airborne -> JUMP_AIR. Structural re-entry is legal — the
	# one-air-attack-per-jump rule is the CONTROLLER's latch (Task 3), not the FSM's.
	_check(sm.request(CSM.State.JUMP_AIR), "AIR_FAST_ATTACK -> JUMP_AIR allowed (recovered airborne)")
	_check(sm.request(CSM.State.AIR_HEAVY_ATTACK), "JUMP_AIR -> AIR_HEAVY_ATTACK allowed")
	_check(not sm.request(CSM.State.FAST_ATTACK), "AIR_HEAVY_ATTACK -> FAST_ATTACK rejected (no ground attacks in air)")
	_check(not sm.request(CSM.State.AIR_FAST_ATTACK), "AIR_HEAVY_ATTACK -> AIR_FAST_ATTACK rejected (no air chains)")
	_check(not sm.request(CSM.State.IDLE), "AIR_HEAVY_ATTACK -> IDLE rejected (must land)")
	# Landing cancel target.
	_check(sm.request(CSM.State.JUMP_LAND), "AIR_HEAVY_ATTACK -> JUMP_LAND allowed (landing cancel)")
	# Forward/back jumps can also attack.
	var sm2 := CSM.new()
	sm2.request(CSM.State.JUMP_START)
	sm2.request(CSM.State.JUMP_F)
	_check(sm2.request(CSM.State.AIR_HEAVY_ATTACK), "JUMP_F -> AIR_HEAVY_ATTACK allowed")
	var sm3 := CSM.new()
	sm3.request(CSM.State.JUMP_START)
	sm3.request(CSM.State.JUMP_B)
	_check(sm3.request(CSM.State.AIR_FAST_ATTACK), "JUMP_B -> AIR_FAST_ATTACK allowed")
	# Reactions still interrupt air attacks.
	sm3.force(CSM.State.HITSTUN)
	_check(sm3.state == CSM.State.HITSTUN, "force(HITSTUN) from AIR_FAST_ATTACK works")
	# Category predicates — these drive gravity, landing, and hitbox resolution.
	_check(CSM.is_airborne(CSM.State.AIR_FAST_ATTACK), "AIR_FAST_ATTACK is airborne")
	_check(CSM.is_airborne(CSM.State.AIR_HEAVY_ATTACK), "AIR_HEAVY_ATTACK is airborne")
	_check(CSM.is_attacking(CSM.State.AIR_FAST_ATTACK), "AIR_FAST_ATTACK is attacking")
	_check(CSM.is_attacking(CSM.State.AIR_HEAVY_ATTACK), "AIR_HEAVY_ATTACK is attacking")
	_check(CSM.is_busy(CSM.State.AIR_FAST_ATTACK), "AIR_FAST_ATTACK is busy")
	_check(not CSM.is_actionable(CSM.State.AIR_FAST_ATTACK), "AIR_FAST_ATTACK not actionable")
	_check(not CSM.is_grounded(CSM.State.AIR_HEAVY_ATTACK), "AIR_HEAVY_ATTACK not grounded")


func _test_convenience_wrappers() -> void:
	var sm := CSM.new()
	sm.on_hit()
	_check(sm.state == CSM.State.HITSTUN, "on_hit() -> HITSTUN")
	sm.reset()
	sm.on_blocked()
	_check(sm.state == CSM.State.BLOCKSTUN, "on_blocked() -> BLOCKSTUN")
	sm.reset()
	sm.on_launched()
	_check(sm.state == CSM.State.KNOCKDOWN, "on_launched() -> KNOCKDOWN")
	sm.reset()
	sm.on_ko()
	_check(sm.state == CSM.State.KO, "on_ko() -> KO")
