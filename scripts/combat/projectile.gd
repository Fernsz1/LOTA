class_name Projectile
extends Node2D
## 3.2 — a live fire-and-forget moving hitbox. main.gd spawns it from a
## ProjectileData (on an attack's spawn frame), calls step() each frame, resolves
## its hitbox vs the opponent, and frees it on hit/block/range. Movement is in
## step() (NOT _physics_process) so main.gd controls ordering + hitstop freeze.

# Preloaded (not the bare class_name) so this compiles under headless --script
# tests, where the project's global class registry isn't loaded. PD is ProjectileData.
const PD := preload("res://scripts/combat/projectile_data.gd")

var data: PD = null
var facing: int = 1
var owner_index: int = 1
var _travelled: float = 0.0
var _expired: bool = false

@onready var _box: ColorRect = $Box

func setup(p_data: PD, origin: Vector2, p_facing: int, p_owner_index: int) -> void:
	data = p_data
	facing = p_facing
	owner_index = p_owner_index
	position = origin
	_travelled = 0.0
	_expired = false

func _ready() -> void:
	# Debug box (red = hitbox, 2.1 colour code). Mirrors the local hitbox; flips with facing.
	if _box != null and data != null:
		_box.color = Color(1, 0, 0, 0.5)
		_box.size = data.hitbox.size
		_box.position = data.hitbox.position
		if facing < 0:
			_box.position.x = -data.hitbox.position.x - data.hitbox.size.x

## One frame of straight-line travel. Expires at max_range. Called by main.gd.
func step() -> void:
	if _expired or data == null:
		return
	var dx: float = data.speed * facing
	position.x += dx
	if _box != null:
		_box.position.x = (data.hitbox.position.x if facing > 0 else -data.hitbox.position.x - data.hitbox.size.x)
	_travelled += absf(dx)
	if _travelled >= data.max_range:
		expire()

func is_expired() -> bool:
	return _expired

## World-space hitbox (mirrored by facing); empty once expired (cheap early-out).
func get_hitboxes() -> Array[Rect2]:
	if _expired or data == null:
		var empty: Array[Rect2] = []
		return empty
	return [CombatBoxes.to_world(data.hitbox, position, facing)]

## Mark dead; main.gd frees it during culling.
func expire() -> void:
	_expired = true
