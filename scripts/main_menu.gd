extends Control
## Main menu — entry point (project.godot run/main_scene). Play/Training swap the
## scene outright; Settings opens an in-place overlay so the menu stays underneath.

@onready var _settings_panel: Control = $SettingsPanel
@onready var _volume_slider: HSlider = $SettingsPanel/Panel/VBox/VolumeRow/VolumeSlider
@onready var _fullscreen_check: CheckButton = $SettingsPanel/Panel/VBox/FullscreenRow/FullscreenCheck

var _master_bus: int = AudioServer.get_bus_index("Master")


func _ready() -> void:
	_volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(_master_bus))
	_fullscreen_check.button_pressed = get_window().mode == Window.MODE_FULLSCREEN


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_training_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/training.tscn")


func _on_leaderboards_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/leaderboards.tscn")


func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _on_settings_close_pressed() -> void:
	_settings_panel.visible = false


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(value))


func _on_fullscreen_toggled(pressed: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if pressed else Window.MODE_WINDOWED
