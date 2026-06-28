class_name HitResolver
extends RefCounted
## Pure hit-resolution decision (2.4). No Node, no physics — given the box-overlap
## result plus a little defender context, decide whether a contact is a clean hit,
## a block, or nothing. main.gd does the box math (CombatBoxes.overlaps) and applies
## the consequences; this class only classifies, so it's unit-testable headless.

# Preloaded (not the bare class_name) so this compiles under headless --script tests,
# where the project's global class registry isn't loaded.
const CSM := preload("res://scripts/fsm/character_state_machine.gd")

enum Outcome { NONE, HIT, BLOCK }

## A defender is guarding iff it is in an actionable ground state (IDLE/WALK_F/WALK_B/
## CROUCH/BLOCK — never mid-attack, airborne, or in a reaction) AND holding the
## away-from-attacker direction. Block model is hold-back (2.4 decision); stand-block
## (WALK_B) and crouch-block (CROUCH) both guard every v1 attack (all mids).
static func is_guarding(defender_state: int, holding_back: bool) -> bool:
	return holding_back and CSM.is_actionable(defender_state)

## Classify a contact. No overlap or an invulnerable defender → NONE; a guarding
## defender → BLOCK; otherwise a clean HIT.
static func classify(overlapping: bool, invulnerable: bool, guarding: bool) -> Outcome:
	if not overlapping or invulnerable:
		return Outcome.NONE
	if guarding:
		return Outcome.BLOCK
	return Outcome.HIT
