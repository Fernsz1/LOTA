extends CanvasLayer
## Read-only debug HUD: frame, FPS, per-player FSM state and input history.
## Toggle with the `debug_panel` action (F2). Off by default in both training
## and versus (main.gd/training_main.gd force it at _ready()) — a real match
## never shows this panel unless F2 is pressed.
## Cosmetic → updates in _process; never writes game state.

@onready var _frame_label: Label = $Panel/VBox/Frame
@onready var _fps_label: Label = $Panel/VBox/FPS
@onready var _state_labels: Array[Label] = [$Panel/VBox/P1State, $Panel/VBox/P2State]
@onready var _input_labels: Array[Label] = [$Panel/VBox/P1Input, $Panel/VBox/P2Input]

var _fps_accum: float = 0.0
var _last_input: Array[int] = [-1, -1]


func _ready() -> void:
	for p in 2:
		set_state(p + 1, "—")


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("debug_panel"):
		visible = not visible
	if not visible:
		return
	_frame_label.text = "frame %d" % GameClock.frame
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		_fps_label.text = "fps   %d" % int(Engine.get_frames_per_second())
	_update_history()


## Called by CharacterController each physics frame. player is 1-based.
## Virtual players (3+) have no label slot; skip silently.
func set_state(player: int, text: String) -> void:
	if player - 1 >= _state_labels.size():
		return
	_state_labels[player - 1].text = "P%d  %s" % [player, text]


func _update_history() -> void:
	if not has_node("/root/InputManager"):
		return
	for i in 2:
		var buf: InputBuffer = InputManager.get_buffer(i + 1)
		var head: int = buf.get_state(0)
		if head == _last_input[i]:
			continue
		_last_input[i] = head
		_input_labels[i].text = "P%d  %s" % [i + 1, _format_history(buf)]


func _format_history(buf: InputBuffer) -> String:
	var parts: PackedStringArray = []
	var prev_token: String = ""
	for age in 16:
		var s: int = buf.get_state(age)
		var token: String = str(_numpad(s)) + _buttons(s)
		if token == prev_token:
			continue
		prev_token = token
		parts.append(token)
	return " ".join(parts)


func _numpad(s: int) -> int:
	var x: int = (1 if s & InputBuffer.RIGHT else 0) - (1 if s & InputBuffer.LEFT else 0)
	var y: int = (1 if s & InputBuffer.UP else 0) - (1 if s & InputBuffer.DOWN else 0)
	return 5 + x + 3 * y


func _buttons(s: int) -> String:
	var out: String = ""
	if s & InputBuffer.FAST: out += "F"
	if s & InputBuffer.HEAVY: out += "H"
	if s & InputBuffer.SKILL: out += "S"
	if s & InputBuffer.ULTIMATE: out += "U"
	return out
