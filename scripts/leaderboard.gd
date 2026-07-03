extends Node
## Persistent local win leaderboard. Autoloaded as `Leaderboard`. Counts a player's
## match wins keyed by their entered name (upper-cased), regardless of which
## character they played — matchup-agnostic by design. Written to disk immediately
## on every win so it survives a crash, not just a clean quit.

const SAVE_PATH := "user://leaderboard.json"

var _wins: Dictionary = {}   # String (upper-cased name) -> int


func _ready() -> void:
	_load()


## Records a win for `player_name` and persists immediately. Blank names (e.g. a
## scene entered directly, bypassing name entry) are not recorded.
func record_win(player_name: String) -> void:
	var key: String = player_name.strip_edges().to_upper()
	if key == "":
		return
	_wins[key] = int(_wins.get(key, 0)) + 1
	_save()


## Entries as [{"name": String, "wins": int}, ...], sorted by wins descending.
func get_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in _wins:
		entries.append({"name": key, "wins": int(_wins[key])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wins"] > b["wins"])
	return entries


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_wins = parsed


func _save() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_wins))
