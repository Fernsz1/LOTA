extends Node2D
## Main scene root. Spawns two player boxes and wires them to the debug overlay.
## Stage walls and player-vs-player pushboxes added in 1.5.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0

@onready var _overlay: Node = $DebugOverlay
@onready var _p1: CharacterController = $P1
@onready var _p2: CharacterController = $P2


func _ready() -> void:
	# Each input event dispatched immediately — reduces latency on high-Hz displays.
	Input.use_accumulated_input = false
	_p1.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)
	_p2.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)
