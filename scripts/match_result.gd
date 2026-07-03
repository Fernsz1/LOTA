extends Control
## Post-match results screen (2.6). Reached once MatchManager holds on the deciding
## win for MATCH_END_HOLD frames. Shows the winner's entered name (Title) and their
## placeholder swatch + character name (CenterCard) — no character art yet, /art is
## still empty (see docs/conventions.md) — and routes onward: Rematch back to
## Character Select (a "rematch" may pick different characters, so it's really just
## Character Select relabeled), or Main Menu.

@onready var _title: Label = $Title
@onready var _swatch: ColorRect = $CenterCard/Swatch
@onready var _character_label: Label = $CenterCard/CharacterLabel


func _ready() -> void:
	var winner: int = MatchSelection.winner
	var data: CharacterData = MatchSelection.p1_data if winner == 1 else MatchSelection.p2_data
	var color: Color = MatchSelection.p1_color if winner == 1 else MatchSelection.p2_color
	var player_name: String = MatchSelection.p1_name if winner == 1 else MatchSelection.p2_name
	_title.text = "%s WINS" % player_name
	_swatch.color = color
	_character_label.text = "AS " + (data.character_name.to_upper() if data != null else "P%d" % winner)


func _on_rematch_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
