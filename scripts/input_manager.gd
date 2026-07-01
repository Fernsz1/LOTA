extends Node
## Polls both local players each physics frame into ring buffers. Autoloaded as
## `InputManager` (no class_name — singleton). Direct per-frame poll = timing-
## affecting (conventions → "Signals vs direct calls").
## Players 1-2 are hardware-polled. Players 3-4 are virtual (training dummies)
## driven via set_override; they return 0 when no override is set.

const PLAYER_COUNT: int = 4       # hardware (1-2) + virtual dummies (3-4)
const HARDWARE_PLAYERS: int = 2   # only p1/p2 read from the InputMap

# action suffix → bit (InputMap actions are "p<n>_<suffix>").
const _ACTIONS := {
	"left": InputBuffer.LEFT, "right": InputBuffer.RIGHT,
	"up": InputBuffer.UP, "down": InputBuffer.DOWN,
	"fast": InputBuffer.FAST, "heavy": InputBuffer.HEAVY,
	"skill": InputBuffer.SKILL, "ultimate": InputBuffer.ULTIMATE,
}

var _players: Array[InputBuffer] = []
var _action_bits: Array = []   # per player: Array of [StringName action, int bit]
var _overrides: Array[int] = [-1, -1, -1, -1]   # 4.1: -1 = use hardware; >=0 = inject this bitmask

func _ready() -> void:
	for p in range(1, PLAYER_COUNT + 1):
		var pairs: Array = []
		if p <= HARDWARE_PLAYERS:
			for suffix in _ACTIONS:
				pairs.append([StringName("p%d_%s" % [p, suffix]), _ACTIONS[suffix]])
		_action_bits.append(pairs)   # virtual players get an empty list → _poll returns 0
		_players.append(InputBuffer.new())

func _physics_process(_delta: float) -> void:
	for i in PLAYER_COUNT:
		_players[i].push(_poll(i))

## player is 1-based.
func get_buffer(player: int) -> InputBuffer:
	return _players[player - 1]

## 4.1 — replace hardware input for one player with a fixed bitmask each frame.
## Call each frame from TrainingManager; takes effect on the next InputManager poll.
func set_override(player: int, bits: int) -> void:
	_overrides[player - 1] = bits

func clear_override(player: int) -> void:
	_overrides[player - 1] = -1

func _poll(index: int) -> int:
	if _overrides[index] >= 0:
		return _overrides[index]
	var state: int = 0
	for pair in _action_bits[index]:
		if Input.is_action_pressed(pair[0]):
			state |= pair[1]
	return state
