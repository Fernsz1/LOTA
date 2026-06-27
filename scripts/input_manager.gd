extends Node
## Polls both local players each physics frame into ring buffers. Autoloaded as
## `InputManager` (no class_name — singleton). Direct per-frame poll = timing-
## affecting (conventions → "Signals vs direct calls").

const PLAYER_COUNT: int = 2

# action suffix → bit (InputMap actions are "p<n>_<suffix>").
const _ACTIONS := {
	"left": InputBuffer.LEFT, "right": InputBuffer.RIGHT,
	"up": InputBuffer.UP, "down": InputBuffer.DOWN,
	"fast": InputBuffer.FAST, "heavy": InputBuffer.HEAVY,
	"skill": InputBuffer.SKILL, "ultimate": InputBuffer.ULTIMATE,
}

var _players: Array[InputBuffer] = []
var _action_bits: Array = []   # per player: Array of [StringName action, int bit]

func _ready() -> void:
	for p in range(1, PLAYER_COUNT + 1):
		var pairs: Array = []
		for suffix in _ACTIONS:
			pairs.append([StringName("p%d_%s" % [p, suffix]), _ACTIONS[suffix]])
		_action_bits.append(pairs)
		_players.append(InputBuffer.new())

func _physics_process(_delta: float) -> void:
	for i in PLAYER_COUNT:
		_players[i].push(_poll(i))

## player is 1-based.
func get_buffer(player: int) -> InputBuffer:
	return _players[player - 1]

func _poll(index: int) -> int:
	var state: int = 0
	for pair in _action_bits[index]:
		if Input.is_action_pressed(pair[0]):
			state |= pair[1]
	return state
