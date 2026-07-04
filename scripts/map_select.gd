extends Control
## Map Select (7.6). Player picks a stage by clicking one of 5 Philippines regions.
## Regions are built at runtime from data/map_regions.json. Confirming sets
## MatchSelection.stage_data and advances to the loading screen. Replaces the old
## grid stage_select in the character-select -> stage -> loading flow.

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
	get_viewport().physics_object_picking = true
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
		node.region_hovered.connect(_on_region_hovered)
		node.region_clicked.connect(select_region)
		_nodes[id] = node
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	select_region(_selected_id)


func _active_id() -> int:
	return _hovered_id if _hovered_id != 0 else _selected_id


func _on_region_hovered(id: int) -> void:
	if _locked:
		return
	_hovered_id = id
	_refresh()


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
