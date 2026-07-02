extends Control
## Post-select title card: shows each locked-in fighter before the match starts.
## Auto-advances after DISPLAY_SECONDS, or immediately on any key press.

const DISPLAY_SECONDS := 2.5

@onready var _p1_name: Label = $P1Card/NameLabel
@onready var _p1_swatch: ColorRect = $P1Card/Swatch
@onready var _p2_name: Label = $P2Card/NameLabel
@onready var _p2_swatch: ColorRect = $P2Card/Swatch

var _advanced: bool = false


func _ready() -> void:
	_p1_name.text = MatchSelection.p1_data.character_name.to_upper() if MatchSelection.p1_data else "P1"
	_p1_swatch.color = MatchSelection.p1_color
	_p2_name.text = MatchSelection.p2_data.character_name.to_upper() if MatchSelection.p2_data else "P2"
	_p2_swatch.color = MatchSelection.p2_color

	await get_tree().create_timer(DISPLAY_SECONDS).timeout
	_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_advance()


func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	if MatchSelection.pending_scene != null:
		get_tree().change_scene_to_packed(MatchSelection.pending_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
