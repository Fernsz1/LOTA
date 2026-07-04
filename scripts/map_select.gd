@tool
extends Control
## Map Select (7.6). Player picks a stage by clicking one of 5 Philippines regions.
## Regions are built from data/map_regions.json at runtime AND in the editor (@tool),
## so the silhouette previews live while editing the scene. Hit-testing is
## point-in-polygon (Geometry2D). Confirming sets MatchSelection.stage_data and
## advances to the loading screen. Replaces the old grid stage_select in the
## character-select -> stage -> loading flow.

signal stage_confirmed(region_id: int, stage_name: String, fighter: String)

const DATA_PATH := "res://data/map_regions.json"
const MAP_CENTER := Vector2(470, 392)   # where the map's bbox center sits on screen

@onready var _map_root: Node2D = $MapContainer
@onready var _fighter_label: Label = $Header/FighterValue
@onready var _tt_title: Label = $Tooltip/Title
@onready var _tt_region: Label = $Tooltip/RegionNum
@onready var _tt_stage: Label = $Tooltip/StageValue
@onready var _tt_unlocks: Label = $Tooltip/UnlocksValue
@onready var _tt_story: Label = $Tooltip/StoryValue
@onready var _hub_stage: Label = $ConfirmHub/StageValue
@onready var _confirm_btn: Button = $ConfirmHub/ConfirmButton

var _regions: Dictionary = {}         # id -> region dict
var _nodes: Dictionary = {}           # id -> MapRegion
var _hovered_id: int = 0
var _selected_id: int = 4
var _locked: bool = false


func _ready() -> void:
	_build_map()
	select_region(_selected_id)
	if Engine.is_editor_hint():
		return
	_confirm_btn.pressed.connect(_on_confirm_pressed)


func _build_map() -> void:
	# Rebuild from scratch (the editor re-runs _ready on scene reload). Children are
	# created without an owner, so they render in the editor but are never saved.
	for child in _map_root.get_children():
		child.free()
	_regions.clear()
	_nodes.clear()
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var map_size := Vector2(float(doc["map_size"][0]), float(doc["map_size"][1]))
	_map_root.position = MAP_CENTER - map_size * 0.5
	for data: Dictionary in doc["regions"]:
		var id := int(data["id"])
		_regions[id] = data
		var node := MapRegion.new()
		_map_root.add_child(node)
		node.setup(data)
		node.set_base_y(0.0)
		_nodes[id] = node


func _active_id() -> int:
	return _hovered_id if _hovered_id != 0 else _selected_id


func _region_at() -> int:
	# id of the region under the mouse, or 0 if none. Point tested in MapContainer space.
	var local: Vector2 = _map_root.to_local(get_global_mouse_position())
	for rid: int in _nodes:
		if _nodes[rid].contains_point(local):
			return rid
	return 0


func _gui_input(event: InputEvent) -> void:
	if _locked or Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		var id := _region_at()
		if id != _hovered_id:      # 0 when the cursor is off the map -> falls back to selected
			_hovered_id = id
			_refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _region_at()
		if id != 0:
			select_region(id)


func select_region(id: int) -> void:
	if _locked:
		return
	_selected_id = id
	_refresh()
	var d: Dictionary = _regions[id]
	_hub_stage.text = str(d["stage_name"])


func _refresh() -> void:
	var active := _active_id()
	for rid: int in _nodes:
		_nodes[rid].set_active(rid == active)
	var d: Dictionary = _regions[active]
	_fighter_label.text = str(d["fighter_name"])
	_tt_title.text = str(d["display_name"]).to_upper()
	_tt_region.text = "REGION %d" % int(d["region_number"])
	_tt_stage.text = str(d["stage_name"])
	_tt_unlocks.text = str(d["fighter_name"])
	_tt_story.text = str(d["story_context"])
	_tt_title.add_theme_color_override("font_color", Color(str(d["accent_color"])))


func lock_selection() -> void:
	var d: Dictionary = _regions[_selected_id]
	MatchSelection.stage_data = load(str(d["stage_data_path"]))
	_locked = true
	stage_confirmed.emit(_selected_id, str(d["stage_name"]), str(d["fighter_name"]))


func _on_confirm_pressed() -> void:
	if _locked:
		return
	var tw := create_tween()
	tw.tween_property(_confirm_btn, "scale", Vector2(0.94, 0.94), 0.06)
	tw.tween_property(_confirm_btn, "scale", Vector2.ONE, 0.06)
	lock_selection()
	_confirm_btn.text = "STAGE LOCKED IN"
	_confirm_btn.add_theme_color_override("font_color", Color.WHITE)
	_confirm_btn.self_modulate = Color("2ecc71")
	await get_tree().create_timer(0.25).timeout
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
