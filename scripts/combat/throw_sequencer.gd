class_name ThrowSequencer
extends RefCounted
## Orchestrates ONE connected throw between two CharacterControllers (6.4).
## The scene owns the instance (cross-character logic lives at the scene root,
## like pushboxes/facing): call try_start() to detect a connect, then step()
## once per unfrozen physics frame until it returns true.
##
## Flow: attacker GRAB_ATTEMPT + live grab box overlapping a grabbable defender
## → attacker THROW_RELEASE / victim forced GRABBED (+hitstop both). Each frame
## the victim is snapped to a hold offset in front of the attacker. Within the
## move's tech_window a buffered FAST press by the victim techs the throw (both
## freed, nudged apart, no damage). After throw_release_frames the slam lands:
## damage + vertical pop into KNOCKDOWN (+hitstop both). If either side leaves
## its throw state early (projectile interrupt, round reset, timer KO) the
## sequence aborts and frees whoever is still held.

const CSM := preload("res://scripts/fsm/character_state_machine.gd")
const Rules := preload("res://scripts/combat/grab_rules.gd")

const HOLD_OFFSET_X: float = 48.0   # > pushbox width (40) so separation stays quiet
const TECH_NUDGE: float = 26.0      # px each side is pushed apart on a tech

var attacker: CharacterController
var victim: CharacterController
var move: MoveData

var _frames_held: int = 0
var _done: bool = false


## Detect + apply a grab connect this frame. Returns a live sequencer, or null.
## Mirrors HitResolver's split: GrabRules decides legality, this applies it.
static func try_start(atk: CharacterController, def: CharacterController) -> ThrowSequencer:
	var grab_move: MoveData = atk.get_grab_move()
	if grab_move == null:
		return null
	var boxes: Array[Rect2] = atk.get_grab_boxes()   # empty outside the active window / after connect
	if boxes.is_empty():
		return null
	if def.is_invulnerable() or not Rules.is_grabbable(def.fsm_state()):
		return null
	if not CombatBoxes.overlaps(boxes, def.get_hurtboxes()):
		return null

	var seq := ThrowSequencer.new()
	seq.attacker = atk
	seq.victim = def
	seq.move = grab_move
	atk.begin_throw()
	def.apply_grabbed()
	atk.apply_hitstop(grab_move.hitstop)
	def.apply_hitstop(grab_move.hitstop)
	seq._snap_victim()   # immediately, so pushboxes never see a mid-connect overlap
	return seq


## Advance one physics frame. Call only while neither fighter is frozen.
## Returns true when the throw is finished (landed, teched, or aborted).
func step() -> bool:
	if _done:
		return true
	# Interrupted from outside (hit out of the throw, round reset, forced KO)?
	if attacker.fsm_state() != CSM.State.THROW_RELEASE \
			or victim.fsm_state() != CSM.State.GRABBED:
		victim.release_from_grab()
		attacker.end_throw()
		_done = true
		return true
	# Tech: victim mashes FAST inside the window → clean escape, no damage.
	# The lookback spans the connect hitstop too: input keeps buffering while the
	# fighters are frozen, but step() doesn't run — a 1-frame edge check would
	# eat every tech pressed during the freeze.
	if _frames_held < move.tech_window:
		var lookback: int = mini(move.tech_window + move.hitstop, InputBuffer.SIZE - 1)
		if InputManager.get_buffer(victim.player_index).pressed_within(InputBuffer.FAST, lookback):
			_tech()
			return true
	_snap_victim()
	_frames_held += 1
	if _frames_held >= move.throw_release_frames:
		attacker.apply_hitstop(move.hitstop)   # impact freeze on the slam
		victim.apply_hitstop(move.hitstop)
		victim.apply_throw(move)               # damage + pop → KNOCKDOWN
		attacker.end_throw()
		_done = true
		return true
	return false


func is_done() -> bool:
	return _done


func _snap_victim() -> void:
	victim.position = Vector2(
		attacker.position.x + HOLD_OFFSET_X * attacker.facing,
		attacker.position.y)


func _tech() -> void:
	victim.release_from_grab()
	attacker.end_throw()
	var dir: float = signf(victim.position.x - attacker.position.x)
	if dir == 0.0:
		dir = float(attacker.facing)
	victim.position.x += TECH_NUDGE * dir
	attacker.position.x -= TECH_NUDGE * dir
	_done = true
