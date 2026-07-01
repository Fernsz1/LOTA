extends Node2D
## Box renderer for development and training mode (reused by 4.3).
## Draws all players' boxes colour-coded and projectile hitboxes.
## Toggle with the `debug_boxes` action (F3). Starts in whatever state
## `visible` is set to in the scene (training = off, match = on).
## Green = hurtbox, red = hitbox, yellow = pushbox (outline).

const COL_HURT: Color = Color(0.2, 0.8, 0.3, 0.45)
const COL_HIT: Color = Color(0.9, 0.2, 0.2, 0.5)
const COL_PUSH: Color = Color(0.9, 0.8, 0.2, 0.9)

@export var players: Array[NodePath] = []
@export var main_path: NodePath

var _main: Node = null
var _controllers: Array[CharacterController] = []
var _enabled: bool = true


func _ready() -> void:
	for p in players:
		_controllers.append(get_node(p))
	if not main_path.is_empty():
		_main = get_node(main_path)
	_enabled = visible   # sync from scene so training can start hidden


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_boxes"):
		_enabled = not _enabled
		visible = _enabled
	if _enabled:
		queue_redraw()


func _draw() -> void:
	for c in _controllers:
		draw_rect(c.get_pushbox(), COL_PUSH, false, 2.0)
		for r in c.get_hurtboxes():
			draw_rect(r, COL_HURT, true)
		for r in c.get_hitboxes():
			draw_rect(r, COL_HIT, true)
	if _main != null:
		for r in _main.get_projectile_hitboxes():
			draw_rect(r, COL_HIT, true)
