class_name GrabRules
extends RefCounted
## Pure grab-legality decision (6.4). Mirrors the HitResolver split: this class
## only decides WHO can be grabbed; ThrowSequencer does the box math and applies
## consequences. No Node, no physics — unit-testable headless.

# Preloaded (not the bare class_name) so this compiles under headless --script
# tests, where the project's global class registry isn't loaded.
const CSM := preload("res://scripts/fsm/character_state_machine.gd")

## A defender can be grabbed iff GROUNDED and free-standing or committed to a
## ground action. Blocking and attack recovery ARE grabbable — that's the
## grappler's payoff. Not grabbable:
## - JUMP_START/airborne: prejump is throw-invulnerable, so jumping escapes grabs;
## - reactions (HITSTUN/BLOCKSTUN/KNOCKDOWN/GRABBED): no throw loops in combos;
## - GETUP/KO: wakeup is invulnerable, KO is terminal;
## - THROW_RELEASE: a thrower mid-throw can be struck, not re-grabbed.
## Caller must ALSO check is_invulnerable() (getup/move invuln), as with strikes.
static func is_grabbable(defender_state: int) -> bool:
	if CSM.is_airborne(defender_state) or defender_state == CSM.State.JUMP_START:
		return false
	if CSM.is_in_reaction(defender_state):
		return false
	if defender_state == CSM.State.GETUP or defender_state == CSM.State.KO \
			or defender_state == CSM.State.THROW_RELEASE:
		return false
	return true
