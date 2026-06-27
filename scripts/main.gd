extends Node2D
## Main scene root. Hosts stage constants, spawns two player boxes, and owns all
## cross-character logic (facing). Runs at physics priority 1 so _physics_process
## fires AFTER both CharacterControllers (priority 0) have moved for this tick.

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
	_update_facing()


# Characters always face each other. Re-derived every frame from positions so
# it stays correct even if an air jump temporarily shifts relative sides.
func _update_facing() -> void:
	var p1_left: bool = _p1.position.x <= _p2.position.x
	_p1.facing = 1 if p1_left else -1
	_p2.facing = -1 if p1_left else 1
