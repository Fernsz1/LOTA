class_name ProjectileData
extends Resource
## 3.2 — flight + hit payload for one projectile type. A spawning MoveData
## references one of these; the live Projectile node reads it each frame. Mirrors
## MoveData's hit half so projectile hits reuse HitResolver unchanged. Frames @60Hz;
## speed/pushback px/frame; hitbox + spawn_offset are LOCAL, facing-right.

@export var projectile_name: String = ""
@export var speed: float = 0.0            # px/frame, travels in owner facing
@export var max_range: float = 0.0        # px from spawn before it despawns
@export var spawn_offset: Vector2 = Vector2.ZERO  # local (facing-right) offset from feet origin
@export var hitbox: Rect2 = Rect2()       # local, facing-right; mirrored by CombatBoxes
@export var damage: int = 0
@export var hitstun: int = 0
@export var blockstun: int = 0
@export var hitstop: int = 0              # applied before stun (feel-reference §4)
@export var pushback_hit: float = 0.0     # px/frame
@export var pushback_block: float = 0.0   # px/frame; block >= hit
@export var causes_knockdown: bool = false

## Sanity-check on load (mirrors MoveData.validate). Hard errors return false.
func validate() -> bool:
	var ok: bool = true
	if speed <= 0.0:
		push_error("ProjectileData '%s': speed must be > 0" % projectile_name)
		ok = false
	if max_range <= 0.0:
		push_error("ProjectileData '%s': max_range must be > 0" % projectile_name)
		ok = false
	if hitbox.size == Vector2.ZERO:
		push_error("ProjectileData '%s': hitbox has zero size" % projectile_name)
		ok = false
	if damage < 0 or hitstun < 0 or blockstun < 0 or hitstop < 0:
		push_error("ProjectileData '%s': negative damage/stun/hitstop" % projectile_name)
		ok = false
	if hitstun <= blockstun:
		push_warning("ProjectileData '%s': hitstun <= blockstun inverts block incentive" % projectile_name)
	return ok
