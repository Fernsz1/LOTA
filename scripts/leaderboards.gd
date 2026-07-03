extends Control
## Leaderboards screen. Reads persisted win counts from Leaderboard (name-keyed,
## not character-keyed) and lists them ranked highest-first.

@onready var _empty_label: Label = $EmptyLabel
@onready var _entries_list: VBoxContainer = $Scroll/EntriesList


func _ready() -> void:
	var entries: Array[Dictionary] = Leaderboard.get_entries()
	_empty_label.visible = entries.is_empty()
	for i in entries.size():
		_add_row(i + 1, entries[i]["name"], entries[i]["wins"])


func _add_row(rank: int, player_name: String, wins: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)

	var rank_label := Label.new()
	rank_label.custom_minimum_size = Vector2(60, 0)
	rank_label.text = "#%d" % rank
	rank_label.add_theme_font_size_override("font_size", 22)
	rank_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(300, 0)
	name_label.text = player_name
	name_label.add_theme_font_size_override("font_size", 22)
	row.add_child(name_label)

	var wins_label := Label.new()
	wins_label.text = "%d WIN%s" % [wins, "" if wins == 1 else "S"]
	wins_label.add_theme_font_size_override("font_size", 22)
	row.add_child(wins_label)

	_entries_list.add_child(row)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
