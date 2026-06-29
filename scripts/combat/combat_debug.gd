extends Node2D
## 2.1 debug box renderer (read-only; reused by training mode 4.3). Draws both
## players' boxes color-coded and runs a live overlap check (real hit resolution is
## 2.4). Must sit at world origin (0,0) so world-space rects map straight to _draw.
## Green = hurtbox, red = hitbox, yellow = pushbox (outline).

const COL_HURT: Color = Color(0.2, 0.8, 0.3, 0.45)
const COL_HIT: Color = Color(0.9, 0.2, 0.2, 0.5)
const COL_PUSH: Color = Color(0.9, 0.8, 0.2, 0.9)

@export var players: Array[NodePath] = []
@export var main_path: NodePath

var _main: Node = null
var _controllers: Array[CharacterController] = []
var _enabled: bool = true          # on by default during development
var _was_contact: bool = false

func _ready() -> void:
	for p in players:
		_controllers.append(get_node(p))
	if not main_path.is_empty():
		_main = get_node(main_path)

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_boxes"):
		_enabled = not _enabled
		visible = _enabled
	if not _enabled:
		return
	_check_contacts()   # read-only detection demo; 2.4 does the real resolution
	queue_redraw()

# Edge-triggered so it logs once per contact, not every frame.
func _check_contacts() -> void:
	if _controllers.size() < 2:
		return
	var a: CharacterController = _controllers[0]
	var b: CharacterController = _controllers[1]
	var hit: bool = CombatBoxes.overlaps(a.get_hitboxes(), b.get_hurtboxes()) \
		or CombatBoxes.overlaps(b.get_hitboxes(), a.get_hurtboxes())
	if hit and not _was_contact:
		print("[2.1] CONTACT @ frame %d" % GameClock.frame)
	_was_contact = hit

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
