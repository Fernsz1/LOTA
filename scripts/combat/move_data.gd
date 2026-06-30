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
@export var projectile: ProjectileData = null   # 3.2: if set, this move spawns a projectile
@export var projectile_spawn_frame: int = -1     # frame_in_state to spawn on; -1 = first active (startup)

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
	if hitboxes.is_empty() and projectile == null:
		push_error("MoveData '%s': needs >=1 hitbox (or a projectile)" % move_name)
		ok = false
	if damage < 0 or hitstun < 0 or blockstun < 0 or hitstop < 0:
		push_error("MoveData '%s': negative damage/stun/hitstop" % move_name)
		ok = false
	if hitstun <= blockstun:
		push_warning("MoveData '%s': hitstun <= blockstun inverts block incentive (feel-reference §7)" % move_name)
	return ok
