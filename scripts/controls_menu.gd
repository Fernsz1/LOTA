extends Control
## Key-rebinding screen opened from Settings. Rows are built from
## ControlsConfig.REMAPPABLE_ACTIONS so the action list has one source of truth.

const ACTION_LABELS := {
	"p1_left": "P1 Left", "p1_right": "P1 Right", "p1_up": "P1 Jump", "p1_down": "P1 Down / Block",
	"p1_fast": "P1 Fast Attack", "p1_heavy": "P1 Heavy Attack", "p1_skill": "P1 Skill", "p1_ultimate": "P1 Ultimate",
	"p2_left": "P2 Left", "p2_right": "P2 Right", "p2_up": "P2 Jump", "p2_down": "P2 Down / Block",
	"p2_fast": "P2 Fast Attack", "p2_heavy": "P2 Heavy Attack", "p2_skill": "P2 Skill", "p2_ultimate": "P2 Ultimate",
}

@onready var _rows: VBoxContainer = $Panel/VBox/Scroll/Rows

var _listening_action: String = ""
var _listening_button: Button = null
var _action_buttons: Dictionary = {}   # action -> Button, so reset can refresh labels


func _ready() -> void:
	for action: String in ControlsConfig.REMAPPABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.custom_minimum_size = Vector2(180, 0)
		label.text = ACTION_LABELS.get(action, action)
		row.add_child(label)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 40)
		btn.text = ControlsConfig.get_key_display(action)
		btn.pressed.connect(_on_rebind_pressed.bind(action, btn))
		row.add_child(btn)

		_rows.add_child(row)
		_action_buttons[action] = btn


func _on_rebind_pressed(action: String, btn: Button) -> void:
	if _listening_action != "":
		return  # already capturing another row's key — ignore extra clicks
	_listening_action = action
	_listening_button = btn
	btn.text = "Press a key…"


func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action == "" or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()

	var action := _listening_action
	var btn := _listening_button
	_listening_action = ""
	_listening_button = null

	if event.keycode == KEY_ESCAPE:
		btn.text = ControlsConfig.get_key_display(action)
		return

	var conflict := ControlsConfig.find_conflict(event.physical_keycode, action)
	if conflict != "":
		_flash_conflict(btn, action, conflict)
		return

	ControlsConfig.rebind(action, event.physical_keycode)
	btn.text = ControlsConfig.get_key_display(action)


## Briefly shows which action already owns the pressed key, then reverts the
## button to its (unchanged) current binding. The rebind never happens.
func _flash_conflict(btn: Button, action: String, conflicting_action: String) -> void:
	btn.text = "In use: %s" % ACTION_LABELS.get(conflicting_action, conflicting_action)
	await get_tree().create_timer(1.2).timeout
	btn.text = ControlsConfig.get_key_display(action)


func _on_reset_pressed() -> void:
	_listening_action = ""
	_listening_button = null
	ControlsConfig.reset_to_defaults()
	for action: String in _action_buttons:
		_action_buttons[action].text = ControlsConfig.get_key_display(action)
