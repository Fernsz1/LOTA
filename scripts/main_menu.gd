extends Control
## Main menu — entry point (project.godot run/main_scene). Play/Training swap the
## scene outright; Settings opens an in-place overlay so the menu stays underneath.
## Music/SFX buses are children of Master (audio/default_bus_layout.tres) so Master
## still scales everything while Music/SFX adjust independently.

@onready var _settings_panel: Control = $SettingsPanel
@onready var _controls_panel: Control = $ControlsPanel
@onready var _master_slider: HSlider = $SettingsPanel/Panel/VBox/MasterVolumeRow/MasterVolumeSlider
@onready var _music_slider: HSlider = $SettingsPanel/Panel/VBox/MusicVolumeRow/MusicVolumeSlider
@onready var _sfx_slider: HSlider = $SettingsPanel/Panel/VBox/SFXVolumeRow/SFXVolumeSlider
@onready var _fullscreen_check: CheckButton = $SettingsPanel/Panel/VBox/FullscreenRow/FullscreenCheck

var _master_bus: int = AudioServer.get_bus_index("Master")
var _music_bus: int = AudioServer.get_bus_index("Music")
var _sfx_bus: int = AudioServer.get_bus_index("SFX")


func _ready() -> void:
	_master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(_master_bus))
	_music_slider.value  = db_to_linear(AudioServer.get_bus_volume_db(_music_bus))
	_sfx_slider.value    = db_to_linear(AudioServer.get_bus_volume_db(_sfx_bus))
	_fullscreen_check.button_pressed = get_window().mode == Window.MODE_FULLSCREEN


## Esc opens Settings from the bare menu, and otherwise backs out one layer
## (Controls → Settings → closed). While the controls screen is capturing a
## rebind it consumes Esc itself first, so this never fires mid-capture.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	get_viewport().set_input_as_handled()
	if _controls_panel.visible:
		_on_controls_back_pressed()
	elif _settings_panel.visible:
		_on_settings_close_pressed()
	else:
		_on_settings_pressed()


func _on_play_pressed() -> void:
	MatchSelection.training = false
	get_tree().change_scene_to_file("res://scenes/player_names.tscn")


func _on_training_pressed() -> void:
	# 7.5 — training now shares the versus select flow (character → stage);
	# the flag makes stage_select cut to training.tscn instead of the match.
	# Name entry is skipped: training has no leaderboard.
	MatchSelection.training = true
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_leaderboards_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/leaderboards.tscn")


func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _on_settings_close_pressed() -> void:
	_settings_panel.visible = false


func _on_controls_pressed() -> void:
	_settings_panel.visible = false
	_controls_panel.visible = true


func _on_controls_back_pressed() -> void:
	_controls_panel.visible = false
	_settings_panel.visible = true


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_master_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(value))


func _on_music_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(value))


func _on_sfx_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(value))


func _on_fullscreen_toggled(pressed: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if pressed else Window.MODE_WINDOWED
