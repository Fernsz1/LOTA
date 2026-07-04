class_name CharacterStateMachine
extends RefCounted
## Hand-rolled FSM shared by every character. Pure logic — no Node, no input,
## no physics. The character controller (1.4) owns one, polls state/frame_in_state
## each _physics_process, and calls tick() once per frame at the end of its update.
## Enforces STRUCTURAL legality only; timing/cancel rules are Phase 2 / 3.5.
## See docs/fsm.md and docs/superpowers/specs/2026-06-27-fsm-architecture-design.md.

signal state_changed(from: State, to: State)

enum State {
	IDLE, WALK_F, WALK_B, CROUCH,
	JUMP_START, JUMP_AIR, JUMP_F, JUMP_B, JUMP_LAND,
	DASH, BACKDASH, BLOCK,
	FAST_ATTACK, HEAVY_ATTACK, SKILL,
	HITSTUN, BLOCKSTUN, KNOCKDOWN, GETUP, KO,
	GRAB_ATTEMPT, GRABBED, THROW_RELEASE,   # 6.4 grabs — appended to keep ordinals stable
	AIR_FAST_ATTACK, AIR_HEAVY_ATTACK,      # air attacks — appended to keep ordinals stable
}

# Targets a reaction may force into (from any non-KO state). GRABBED is the
# victim's entry into a connected throw (6.4).
const _FORCE_TARGETS: Array[State] = [
	State.HITSTUN, State.BLOCKSTUN, State.KNOCKDOWN, State.KO, State.GRABBED,
]

# Where an actionable ground state may go on a player/logic request.
const _ACTIONABLE_EXITS: Array[State] = [
	State.IDLE, State.WALK_F, State.WALK_B, State.CROUCH, State.BLOCK,
	State.JUMP_START, State.DASH, State.BACKDASH,
	State.FAST_ATTACK, State.HEAVY_ATTACK, State.SKILL, State.GRAB_ATTEMPT,
]

var state: State = State.IDLE
var prev_state: State = State.IDLE
var frame_in_state: int = 0

var _entered_this_frame: bool = false


## Player/logic-initiated transition. Re-requesting the current state is a
## harmless no-op (returns true, no reset, no signal) so a polling controller can
## call request(WALK_F) every frame while holding forward. Otherwise applies iff
## structurally legal; returns whether it happened.
func request(next: State) -> bool:
	if next == state:
		return true
	if not can_transition(next):
		return false
	_change_to(next)
	return true


## Reaction/interrupt transition (being hit/blocking/KO'd). Bypasses request
## rules; legal from any non-KO state into a reaction or KO. Re-forcing a reaction
## re-applies it (a fresh hit resets stun).
func force(next: State) -> void:
	assert(state != State.KO, "cannot force out of KO; use reset()")
	assert(next in _FORCE_TARGETS, "force() target must be a reaction or KO state")
	_change_to(next)


## Round reset. The only legal way out of KO.
func reset(to: State = State.IDLE) -> void:
	_change_to(to)


## Advance one physics frame. Call once per _physics_process, at the END of the
## controller's update. The first tick after a transition is absorbed so the
## entry frame reads frame_in_state == 0 (see docs/fsm.md "Frame counter").
func tick() -> void:
	if _entered_this_frame:
		_entered_this_frame = false
	else:
		frame_in_state += 1


## Structural legality of a request from the current state. Defined as explicit
## per-source-category exits — no 20x20 matrix.
func can_transition(to: State) -> bool:
	match state:
		State.KO:
			return false
		State.IDLE, State.WALK_F, State.WALK_B, State.CROUCH, State.BLOCK:
			return to in _ACTIONABLE_EXITS
		State.JUMP_AIR, State.JUMP_F, State.JUMP_B:
			return to == State.JUMP_LAND \
				or to == State.AIR_FAST_ATTACK or to == State.AIR_HEAVY_ATTACK
		State.JUMP_START:
			return to == State.JUMP_AIR or to == State.JUMP_F or to == State.JUMP_B
		State.JUMP_LAND, State.DASH, State.BACKDASH, State.GETUP:
			return to == State.IDLE
		State.FAST_ATTACK, State.HEAVY_ATTACK, State.SKILL:
			return to == State.IDLE or to == State.JUMP_AIR
		State.AIR_FAST_ATTACK, State.AIR_HEAVY_ATTACK:
			# Finished airborne → back to neutral fall; touched the floor → landing
			# cancel. Never directly to IDLE and never into another attack (no air chains).
			return to == State.JUMP_AIR or to == State.JUMP_LAND
		State.HITSTUN, State.BLOCKSTUN:
			return to == State.IDLE or to == State.JUMP_AIR
		State.KNOCKDOWN:
			return to == State.GETUP
		# 6.4 grabs: attempt resolves to IDLE (whiff) or THROW_RELEASE (connect);
		# the throw and the held victim both resolve to IDLE (release/tech/abort).
		State.GRAB_ATTEMPT:
			return to == State.IDLE or to == State.THROW_RELEASE
		State.THROW_RELEASE, State.GRABBED:
			return to == State.IDLE
	return false


# --- Convenience entry points for the combat layer (Phase 2) ---
func on_hit() -> void:
	force(State.HITSTUN)

func on_launched() -> void:
	force(State.KNOCKDOWN)

func on_blocked() -> void:
	force(State.BLOCKSTUN)

func on_ko() -> void:
	force(State.KO)


# --- State category predicates (the "data-light rules") ---
static func is_airborne(s: State) -> bool:
	return s == State.JUMP_AIR or s == State.JUMP_F or s == State.JUMP_B \
		or s == State.AIR_FAST_ATTACK or s == State.AIR_HEAVY_ATTACK

static func is_grounded(s: State) -> bool:
	return not is_airborne(s)

static func is_actionable(s: State) -> bool:
	return s == State.IDLE or s == State.WALK_F or s == State.WALK_B \
		or s == State.CROUCH or s == State.BLOCK

static func is_attacking(s: State) -> bool:
	return s == State.FAST_ATTACK or s == State.HEAVY_ATTACK or s == State.SKILL \
		or s == State.AIR_FAST_ATTACK or s == State.AIR_HEAVY_ATTACK

static func is_in_reaction(s: State) -> bool:
	return s == State.HITSTUN or s == State.BLOCKSTUN or s == State.KNOCKDOWN \
		or s == State.GRABBED

static func is_busy(s: State) -> bool:
	return s == State.JUMP_START or s == State.JUMP_LAND or s == State.DASH \
		or s == State.BACKDASH or is_attacking(s) or s == State.GETUP \
		or s == State.GRAB_ATTEMPT or s == State.THROW_RELEASE

static func is_ko(s: State) -> bool:
	return s == State.KO


func _change_to(next: State) -> void:
	prev_state = state
	state = next
	frame_in_state = 0
	_entered_this_frame = true
	state_changed.emit(prev_state, next)
