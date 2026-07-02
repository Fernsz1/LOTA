extends Control
## Leaderboards screen. Placeholder until match results are persisted somewhere.

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
