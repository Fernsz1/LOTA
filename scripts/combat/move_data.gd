class_name MoveData
extends Resource
## One move's frame data (2.2) — the authoritative combat layer; animation syncs on
## top (conventions "How frame data is authored"; feel-reference §2–3). Frames are
## integer @60Hz. Hitboxes are LOCAL facing-right Rect2 (the controller mirrors them
## via CombatBoxes). on_block/on_hit are DERIVED, never stored.
##
## v1 storage = ONE hitbox set live across the whole active window. Callers read via
## is_active()/hitboxes_at(), so multi-hit can arrive later as an optional
## active_windows array WITHOUT changing single-hit moves or callers (see docs/combat.md).

# Preloaded (not the bare class_name) so this compiles under headless --script
# tests, where the project's global class registry isn't loaded (same pattern
# as hit_resolver.gd). PD is ProjectileData.
const PD := preload("res://scripts/combat/projectile_data.gd")

@export var move_name: String = ""
@export var startup: int = 0
@export var active: int = 1
@export var recovery: int = 0
@export var hitboxes: Array[Rect2] = []     # local, facing-right; live every active frame
@export var damage: int = 0
@export var hitstun: int = 0
@export var blockstun: int = 0
@export var hitstop: int = 0                 # applied before hitstun (feel-reference §4)
@export var pushback_hit: float = 0.0        # px/frame
@export var pushback_block: float = 0.0      # px/frame; block ≥ hit
@export var causes_knockdown: bool = false   # 2.5: on hit, force KNOCKDOWN instead of HITSTUN
@export var invuln_startup: int = 0   # 3.4: frames of invuln from move start (e.g. DP anti-air); 0 = none
@export var projectile: PD = null   # 3.2: if set, this move spawns a projectile (ProjectileData)
@export var projectile_spawn_frame: int = -1     # frame_in_state to spawn on; -1 = first active (startup)
@export var cancel_window_start: int = -1  # 3.5: frame_in_state when cancel input is accepted; -1 = no cancel
@export var cancel_window_end: int = -1    # 3.5: frame_in_state when cancel closes; -1 = last active frame (startup+active-1)
@export var move_velocity: float = 0.0     # 6.3: px/frame along facing (+x = forward) while in the window; 0 = rooted
@export var move_velocity_start: int = 0   # 6.3: first frame_in_state the self-movement applies
@export var move_velocity_end: int = -1    # 6.3: last frame_in_state (inclusive); -1 = last active frame (startup+active-1)

# 6.4 — command grabs. When is_grab, the controller enters GRAB_ATTEMPT instead
# of a strike state and `hitboxes` become the GRAB box (checked vs hurtboxes,
# unblockable, gated by GrabRules). startup/active/recovery keep their meaning
# (active = connect window, recovery = whiff punish). hitstun/blockstun unused.
@export var is_grab: bool = false
@export var throw_release_frames: int = 30   # length of THROW_RELEASE; damage lands at the end
@export var tech_window: int = 8             # frames from GRABBED entry where victim FAST techs; 0 = untechable
@export var throw_launch_y: float = -6.0     # victim vertical pop at release (falls into KNOCKDOWN)

# 6.2 — strike counter (Luis). When is_counter, the move is a STANCE, not a
# strike: `active` is the counter window, `hitboxes` stays empty, and
# damage/causes_knockdown/hitstop/pushback_hit are the RETALIATION applied to
# the attacker on trigger (via the normal apply_hit path, roles swapped).
# hitstun/blockstun are unused (like grabs). Raw only — never a cancel target.
@export var is_counter: bool = false

# 7.3 — cinematic ultimate (Jerb). When true, the MATCH scene intercepts the
# move on its first frame and plays the scripted UltimateCinematic sequence
# instead of resolving it as a normal strike. `damage` is the TOTAL dealt
# across the scripted hits; hitboxes/stun still author the fallback behaviour
# (training mode, or a start denied by a live throw, runs the move normally).
@export var is_cinematic: bool = false

## Total length; spans are disjoint so it's a clean sum (feel-reference §3).
func total() -> int:
	return startup + active + recovery

## Is the hitbox live on this in-state frame? frame_in_state is 0 on the entry frame
## (FSM contract), so startup frames are 0..startup-1 and the first active frame is
## `startup` (the "startup+1"-th frame in 1-indexed feel-reference §3).
func is_active(frame_in_state: int) -> bool:
	return frame_in_state >= startup and frame_in_state < startup + active

## Local-space hitboxes live this frame (empty otherwise). The stable seam: storage
## can change later (multi-hit) without callers changing.
func hitboxes_at(frame_in_state: int) -> Array[Rect2]:
	if is_active(frame_in_state):
		return hitboxes
	var empty: Array[Rect2] = []
	return empty

## Derived frame advantage assuming a first-active-frame contact (feel-reference §3).
## Hitstop cancels out (freezes both) and is ignored.
func on_block() -> int:
	return blockstun - ((active - 1) + recovery)

func on_hit() -> int:
	return hitstun - ((active - 1) + recovery)

## 3.5 — true while a cancel input is legal on this frame. Defaults to active frames only
## when cancel_window_end is omitted; set it explicitly to extend the window into recovery.
func in_cancel_window(frame_in_state: int) -> bool:
	if cancel_window_start < 0:
		return false
	var end: int = cancel_window_end if cancel_window_end >= 0 else startup + active - 1
	return frame_in_state >= cancel_window_start and frame_in_state <= end

## 6.3 — self-movement (px/frame along facing) live on this in-state frame; 0 otherwise.
## The seam mirroring hitboxes_at(): the controller reads this to drive a move's own
## travel (dash kick, storm kick) without any state-specific logic. Always 0 for the
## default (move_velocity == 0), so existing moves are byte-identical.
func velocity_at(frame_in_state: int) -> float:
	if move_velocity == 0.0:
		return 0.0
	var end: int = move_velocity_end if move_velocity_end >= 0 else startup + active - 1
	if frame_in_state >= move_velocity_start and frame_in_state <= end:
		return move_velocity
	return 0.0

## 3.4 — is the attacker invulnerable on this in-state frame (startup invuln window)?
func is_invuln_at(frame_in_state: int) -> bool:
	return invuln_startup > 0 and frame_in_state < invuln_startup

## 3.2 — frame_in_state on which this move spawns its projectile (if any).
## Defaults to the first active frame (startup).
func projectile_spawn_at() -> int:
	return projectile_spawn_frame if projectile_spawn_frame >= 0 else startup

## Sanity-check on load (conventions: validate with assert/push_error). Hard errors
## return false; soft design smells warn. Call after load() in 2.3.
func validate() -> bool:
	var ok: bool = true
	if startup < 0 or active < 1 or recovery < 0:
		push_error("MoveData '%s': need startup>=0, active>=1, recovery>=0" % move_name)
		ok = false
	if hitboxes.is_empty() and projectile == null and not is_counter:
		push_error("MoveData '%s': needs >=1 hitbox (or a projectile)" % move_name)
		ok = false
	if damage < 0 or hitstun < 0 or blockstun < 0 or hitstop < 0:
		push_error("MoveData '%s': negative damage/stun/hitstop" % move_name)
		ok = false
	if is_counter and is_grab:
		push_error("MoveData '%s': a move cannot be both a counter and a grab" % move_name)
		ok = false
	if is_cinematic and (is_grab or is_counter):
		push_error("MoveData '%s': a cinematic ultimate must be a plain strike" % move_name)
		ok = false
	if is_counter and projectile != null:
		push_error("MoveData '%s': a counter cannot spawn a projectile" % move_name)
		ok = false
	if is_counter and not hitboxes.is_empty():
		push_warning("MoveData '%s': counter hitboxes are never read (the active window is the counter window)" % move_name)
	if is_grab:
		if throw_release_frames < 1:
			push_error("MoveData '%s': grab needs throw_release_frames >= 1" % move_name)
			ok = false
		if tech_window < 0:
			push_error("MoveData '%s': negative tech_window" % move_name)
			ok = false
		if projectile != null:
			push_error("MoveData '%s': a grab cannot also spawn a projectile" % move_name)
			ok = false
	elif not is_counter and hitstun <= blockstun:
		# Strike-only smell — grabs and counters don't use hitstun/blockstun at all.
		push_warning("MoveData '%s': hitstun <= blockstun inverts block incentive (feel-reference §7)" % move_name)
	if move_velocity != 0.0:
		var vend: int = move_velocity_end if move_velocity_end >= 0 else startup + active - 1
		if vend < move_velocity_start:
			push_error("MoveData '%s': move_velocity window inverted (end %d < start %d)" % [move_name, vend, move_velocity_start])
			ok = false
	return ok
