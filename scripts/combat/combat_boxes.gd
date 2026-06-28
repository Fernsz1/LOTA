class_name CombatBoxes
extends RefCounted
## Pure AABB helpers for combat boxes (2.1). No Node, no physics — manual Rect2
## math (dev-plan: manual AABB, never Area2D). Boxes are authored local + facing-
## right; mirror by facing here. Reused by the controller, debug renderer, and 2.4.

## Mirror a local (facing-right) box into world space. X mirrors with facing; Y never.
static func to_world(local: Rect2, origin: Vector2, facing: int) -> Rect2:
	var x: float = origin.x + local.position.x if facing >= 0 \
		else origin.x - local.position.x - local.size.x
	return Rect2(x, origin.y + local.position.y, local.size.x, local.size.y)

## Does any rect in `a` overlap any rect in `b`? Empty set → false (cheap early-out
## when nobody has a live hitbox). Borders excluded: a shared edge is not a hit.
static func overlaps(a: Array[Rect2], b: Array[Rect2]) -> bool:
	for ra in a:
		for rb in b:
			if ra.intersects(rb):
				return true
	return false
