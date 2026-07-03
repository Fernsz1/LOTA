extends Control
## Name-entry screen, shown once per Play (Main Menu -> Play -> here -> Character
## Select). Names feed the winning-screen announcement and the persistent
## Leaderboard (win counts are keyed by name, not character). Blank fields fall
## back to "P1"/"P2" rather than blocking on required input.

@onready var _p1_edit: LineEdit = $CenterContainer/VBox/P1Row/P1NameEdit
@onready var _p2_edit: LineEdit = $CenterContainer/VBox/P2Row/P2NameEdit


func _ready() -> void:
	_p1_edit.grab_focus()


func _on_continue_pressed() -> void:
	var p1_name: String = _p1_edit.text.strip_edges()
	var p2_name: String = _p2_edit.text.strip_edges()
	MatchSelection.p1_name = p1_name if p1_name != "" else "P1"
	MatchSelection.p2_name = p2_name if p2_name != "" else "P2"
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
