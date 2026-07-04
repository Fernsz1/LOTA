extends Control
## Key/gamepad-rebinding screen opened from Settings. Rows are built from
## ControlsConfig.REMAPPABLE_ACTIONS so the action list has one source of truth.
## Each row has two buttons — keyboard and gamepad — rebound independently.

const ACTION_LABELS := {
	"p1_left": "P1 Left", "p1_right": "P1 Right", "p1_up": "P1 Jump", "p1_down": "P1 Down / Block",
	"p1_fast": "P1 Fast Attack", "p1_heavy": "P1 Heavy Attack", "p1_skill": "P1 Skill", "p1_ultimate": "P1 Ultimate",
	"p2_left": "P2 Left", "p2_right": "P2 Right", "p2_up": "P2 Jump", "p2_down": "P2 Down / Block",
	"p2_fast": "P2 Fast Attack", "p2_heavy": "P2 Heavy Attack", "p2_skill": "P2 Skill", "p2_ultimate": "P2 Ultimate",
}

enum ListenMode { NONE, KEY, GAMEPAD }

@onready var _rows: VBoxContainer = $Panel/VBox/Scroll/Rows

var _listen_mode: ListenMode = ListenMode.NONE
var _listening_action: String = ""
var _listening_button: Button = null
var _key_buttons: Dictionary = {}      # action -> Button (keyboard)
var _gamepad_buttons: Dictionary = {}  # action -> Button (gamepad)


func _ready() -> void:
	for action: String in ControlsConfig.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.custom_minimum_size = Vector2(170, 0)
		label.text = ACTION_LABELS.get(action, action)
		row.add_child(label)

		var key_btn := Button.new()
		key_btn.custom_minimum_size = Vector2(110, 40)
		key_btn.text = ControlsConfig.get_key_display(action)
		key_btn.pressed.connect(_on_rebind_pressed.bind(action, key_btn, ListenMode.KEY))
		row.add_child(key_btn)

		var pad_btn := Button.new()
		pad_btn.custom_minimum_size = Vector2(110, 40)
		pad_btn.text = ControlsConfig.get_gamepad_display(action)
		pad_btn.pressed.connect(_on_rebind_pressed.bind(action, pad_btn, ListenMode.GAMEPAD))
		row.add_child(pad_btn)

		_rows.add_child(row)
		_key_buttons[action] = key_btn
		_gamepad_buttons[action] = pad_btn


func _on_rebind_pressed(action: String, btn: Button, mode: ListenMode) -> void:
	if _listen_mode != ListenMode.NONE:
		return  # already capturing another row's input — ignore extra clicks
	_listen_mode = mode
	_listening_action = action
	_listening_button = btn
	btn.text = "Press…"


func _unhandled_key_input(event: InputEvent) -> void:
	if _listen_mode == ListenMode.NONE or not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel_listen()
		return

	if _listen_mode != ListenMode.KEY:
		return  # listening for a gamepad button — stray keyboard presses don't apply

	get_viewport().set_input_as_handled()
	var action := _listening_action
	var btn := _listening_button
	_reset_listen_state()

	var conflict := ControlsConfig.find_conflict(event.physical_keycode, action)
	if conflict != "":
		_flash_conflict(btn, conflict, ControlsConfig.get_key_display.bind(action))
		return

	ControlsConfig.rebind(action, event.physical_keycode)
	btn.text = ControlsConfig.get_key_display(action)


func _unhandled_input(event: InputEvent) -> void:
	if _listen_mode != ListenMode.GAMEPAD or not event is InputEventJoypadButton or not event.pressed:
		return
	get_viewport().set_input_as_handled()

	var action := _listening_action
	var btn := _listening_button
	var device: int = event.device
	_reset_listen_state()

	var conflict := ControlsConfig.find_gamepad_conflict(event.button_index, device, action)
	if conflict != "":
		_flash_conflict(btn, conflict, ControlsConfig.get_gamepad_display.bind(action))
		return

	ControlsConfig.rebind_gamepad(action, event.button_index)
	btn.text = ControlsConfig.get_gamepad_display(action)


func _cancel_listen() -> void:
	var action := _listening_action
	var btn := _listening_button
	var mode := _listen_mode
	_reset_listen_state()
	btn.text = ControlsConfig.get_key_display(action) if mode == ListenMode.KEY \
		else ControlsConfig.get_gamepad_display(action)


func _reset_listen_state() -> void:
	_listen_mode = ListenMode.NONE
	_listening_action = ""
	_listening_button = null


## Briefly shows which action already owns the pressed input, then reverts the
## button to its (unchanged) current binding via restore_fn. The rebind never happens.
func _flash_conflict(btn: Button, conflicting_action: String, restore_fn: Callable) -> void:
	btn.text = "In use: %s" % ACTION_LABELS.get(conflicting_action, conflicting_action)
	await get_tree().create_timer(1.2).timeout
	btn.text = restore_fn.call()


func _on_reset_pressed() -> void:
	_reset_listen_state()
	ControlsConfig.reset_to_defaults()
	for action: String in _key_buttons:
		_key_buttons[action].text = ControlsConfig.get_key_display(action)
		_gamepad_buttons[action].text = ControlsConfig.get_gamepad_display(action)


func _on_back_pressed() -> void:
	_reset_listen_state()
	visible = false
