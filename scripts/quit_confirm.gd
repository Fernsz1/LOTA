extends CanvasLayer
## Reusable ESC overlay for live gameplay scenes (match + training): opens an
## in-game settings panel (audio/fullscreen/controls) instead of quitting outright —
## END MATCH is the only way back to the main menu from here. Runs at
## PROCESS_MODE_ALWAYS so it keeps receiving ui_cancel and UI input while the
## SceneTree is paused; everything else in the scene freezes normally, which is a
## clean fit for a frame-stepped game (docs/conventions.md).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _panel: Control = $Panel
@onready var _controls_panel: Control = $ControlsPanel
@onready var _resume_button: Button = $Panel/VBox/ResumeButton
@onready var _master_slider: HSlider = $Panel/VBox/MasterVolumeRow/MasterVolumeSlider
@onready var _music_slider: HSlider = $Panel/VBox/MusicVolumeRow/MusicVolumeSlider
@onready var _sfx_slider: HSlider = $Panel/VBox/SFXVolumeRow/SFXVolumeSlider
@onready var _fullscreen_check: CheckButton = $Panel/VBox/FullscreenRow/FullscreenCheck

var _master_bus: int = AudioServer.get_bus_index("Master")
var _music_bus: int = AudioServer.get_bus_index("Music")
var _sfx_bus: int = AudioServer.get_bus_index("SFX")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_controls_panel.visible = false
	_master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(_master_bus))
	_music_slider.value  = db_to_linear(AudioServer.get_bus_volume_db(_music_bus))
	_sfx_slider.value    = db_to_linear(AudioServer.get_bus_volume_db(_sfx_bus))
	_fullscreen_check.button_pressed = get_window().mode == Window.MODE_FULLSCREEN


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _controls_panel.visible:
		_on_controls_back_pressed()   # back out of Controls first, stay paused
	elif visible:
		_close()
	else:
		_open()


func _open() -> void:
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func _close() -> void:
	visible = false
	get_tree().paused = false


func _on_resume_pressed() -> void:
	_close()


func _on_end_match_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_controls_pressed() -> void:
	_panel.visible = false
	_controls_panel.visible = true


func _on_controls_back_pressed() -> void:
	_controls_panel.visible = false
	_panel.visible = true


func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(value))


func _on_music_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(value))


func _on_sfx_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(value))


func _on_fullscreen_toggled(pressed: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if pressed else Window.MODE_WINDOWED
