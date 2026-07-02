extends Control
## Genuinely async — loads main.tscn on a background thread and shows real progress,
## rather than faking a timer. Hands the loaded PackedScene to MatchSelection so the
## intro screen can switch to it directly without loading it a second time.

const TARGET_SCENE := "res://scenes/main.tscn"

@onready var _percent_label: Label = $PercentLabel

var _requested: bool = false


func _ready() -> void:
	ResourceLoader.load_threaded_request(TARGET_SCENE)
	_requested = true


func _process(_delta: float) -> void:
	if not _requested:
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if progress.size() > 0:
				_percent_label.text = "%d%%" % int(progress[0] * 100.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			_requested = false
			MatchSelection.pending_scene = ResourceLoader.load_threaded_get(TARGET_SCENE)
			get_tree().change_scene_to_file("res://scenes/character_intro.tscn")
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_requested = false
			push_error("loading_screen: failed to load %s" % TARGET_SCENE)
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
