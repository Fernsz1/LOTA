extends CanvasLayer
## Reusable ESC -> confirm -> quit-to-menu overlay for live gameplay scenes (the
## match and training). Those scenes have no Back button on purpose — a fighter
## mid-combo shouldn't have a clickable exit within reach. Runs at
## PROCESS_MODE_ALWAYS so it keeps receiving ui_cancel and can dismiss itself
## while the SceneTree is paused; everything else in the scene freezes normally,
## which is a clean fit for a frame-stepped game (docs/conventions.md).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _no_button: Button = $Panel/VBox/HBox/NoButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if visible:
		_close()
	else:
		_open()


func _open() -> void:
	visible = true
	get_tree().paused = true
	_no_button.grab_focus()


func _close() -> void:
	visible = false
	get_tree().paused = false


func _on_yes_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_no_pressed() -> void:
	_close()
