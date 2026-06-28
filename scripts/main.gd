extends Node2D
## Main scene root. Hosts stage constants, spawns two player boxes, and owns all
## cross-character logic (pushbox separation, facing). Runs at physics priority 1
## so _physics_process fires AFTER both CharacterControllers (priority 0) have
## moved for this tick.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0

@onready var _overlay: Node = $DebugOverlay
@onready var _p1: CharacterController = $P1
@onready var _p2: CharacterController = $P2


func _ready() -> void:
	# Run AFTER child controllers so pushbox/facing logic sees this tick's positions.
	process_physics_priority = 1
	# Each input event dispatched immediately — reduces latency on high-Hz displays.
	Input.use_accumulated_input = false
	_p1.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)
	_p2.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)


func _physics_process(_delta: float) -> void:
	_resolve_pushboxes()
	_update_facing()


# Prevent horizontal overlap by pushing characters apart along X.
# Y is ignored so airborne characters can jump over each other freely.
# If a push hits a stage wall the surplus is transferred to the other character.
func _resolve_pushboxes() -> void:
	var min_dist: float = CharacterController.PUSH_W
	var dx: float = _p2.position.x - _p1.position.x
	if absf(dx) >= min_dist:
		return

	var push: float = (min_dist - absf(dx)) * 0.5
	var dir: float = 1.0 if dx >= 0.0 else -1.0  # P1 goes left, P2 goes right (or inverse)
	var half_w: float = CharacterController.PUSH_W * 0.5
	var min_x: float = LEFT_WALL_X + half_w
	var max_x: float = RIGHT_WALL_X - half_w

	_p1.position.x -= push * dir
	_p2.position.x += push * dir

	# Transfer wall overflow so a cornered character pushes the opponent instead.
	if _p1.position.x < min_x:
		_p2.position.x += min_x - _p1.position.x
		_p1.position.x = min_x
	elif _p1.position.x > max_x:
		_p2.position.x -= _p1.position.x - max_x
		_p1.position.x = max_x

	if _p2.position.x < min_x:
		_p1.position.x += min_x - _p2.position.x
		_p2.position.x = min_x
	elif _p2.position.x > max_x:
		_p1.position.x -= _p2.position.x - max_x
		_p2.position.x = max_x

	# Safety clamp in case both are simultaneously wall-pressed.
	_p1.position.x = clampf(_p1.position.x, min_x, max_x)
	_p2.position.x = clampf(_p2.position.x, min_x, max_x)


# Characters always face each other. Re-derived every frame from positions so
# it stays correct even if an air jump temporarily shifts relative sides.
func _update_facing() -> void:
	var p1_left: bool = _p1.position.x <= _p2.position.x
	_p1.facing = 1 if p1_left else -1
	_p2.facing = -1 if p1_left else 1
