extends Control
## Key/gamepad-rebinding screen opened from Settings. Actions are laid out in
## two side-by-side columns (Player 1 / Player 2) so every binding is visible
## without scrolling. Rows are built from ControlsConfig.REMAPPABLE_ACTIONS so
## the action list has one source of truth. The panel shows keyboard bindings
## by default; ToggleViewButton switches the whole panel to gamepad bindings.

## Full names, used in conflict messages where the row context isn't enough.
const ACTION_LABELS := {
	"p1_left": "P1 Left", "p1_right": "P1 Right", "p1_up": "P1 Jump", "p1_down": "P1 Down / Block",
	"p1_fast": "P1 Fast Attack", "p1_heavy": "P1 Heavy Attack", "p1_skill": "P1 Skill", "p1_ultimate": "P1 Ultimate",
	"p2_left": "P2 Left", "p2_right": "P2 Right", "p2_up": "P2 Jump", "p2_down": "P2 Down / Block",
	"p2_fast": "P2 Fast Attack", "p2_heavy": "P2 Heavy Attack", "p2_skill": "P2 Skill", "p2_ultimate": "P2 Ultimate",
}

## Row labels keyed by the action suffix — the player prefix is implied by the column.
const ROW_LABELS := {
	"left": "Move Left", "right": "Move Right", "up": "Jump", "down": "Down / Block",
	"fast": "Fast Attack", "heavy": "Heavy Attack", "skill": "Skill", "ultimate": "Ultimate",
}

enum ListenMode { NONE, KEY, GAMEPAD }

@onready var _p1_column: VBoxContainer = $Panel/VBox/Columns/P1Column
@onready var _p2_column: VBoxContainer = $Panel/VBox/Columns/P2Column
@onready var _toggle_button: Button = $Panel/VBox/ButtonRow/ToggleViewButton

var _showing_gamepad := false
var _listen_mode: ListenMode = ListenMode.NONE
var _listening_action: String = ""
var _listening_button: Button = null
var _buttons: Dictionary = {}  # action -> Button (shows key or pad binding per view)


func _ready() -> void:
	for action: String in ControlsConfig.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.custom_minimum_size = Vector2(130, 0)
		label.text = ROW_LABELS.get(action.get_slice("_", 1), action)
		row.add_child(label)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = _binding_display(action)
		btn.pressed.connect(_on_rebind_pressed.bind(action, btn))
		row.add_child(btn)

		var column := _p1_column if action.begins_with("p1_") else _p2_column
		column.add_child(row)
		_buttons[action] = btn

	# Reopening the panel always starts back on the keyboard view, not listening.
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		return
	_reset_listen_state()
	if _showing_gamepad:
		_showing_gamepad = false
		_refresh_view()


func _on_toggle_view_pressed() -> void:
	_reset_listen_state()
	_showing_gamepad = not _showing_gamepad
	_refresh_view()


func _refresh_view() -> void:
	_toggle_button.text = "KEYBOARD CONTROLS" if _showing_gamepad else "GAMEPAD CONTROLS"
	for action: String in _buttons:
		_buttons[action].text = _binding_display(action)


## The action's binding label under the current view (keyboard or gamepad).
func _binding_display(action: String) -> String:
	return ControlsConfig.get_gamepad_display(action) if _showing_gamepad \
		else ControlsConfig.get_key_display(action)


func _on_rebind_pressed(action: String, btn: Button) -> void:
	if _listen_mode != ListenMode.NONE:
		return  # already capturing another row's input — ignore extra clicks
	_listen_mode = ListenMode.GAMEPAD if _showing_gamepad else ListenMode.KEY
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
		_flash_conflict(btn, conflict, _binding_display.bind(action))
		return

	ControlsConfig.rebind(action, event.physical_keycode)
	btn.text = _binding_display(action)


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
		_flash_conflict(btn, conflict, _binding_display.bind(action))
		return

	ControlsConfig.rebind_gamepad(action, event.button_index)
	btn.text = _binding_display(action)


func _cancel_listen() -> void:
	var action := _listening_action
	var btn := _listening_button
	_reset_listen_state()
	btn.text = _binding_display(action)


func _reset_listen_state() -> void:
	if _listening_button != null:
		_listening_button.text = _binding_display(_listening_action)
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
	for action: String in _buttons:
		_buttons[action].text = _binding_display(action)
