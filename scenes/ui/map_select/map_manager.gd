extends Node2D
## Runtime controller for the Map Select screen (MapRoot). Also the single source
## of truth for region grouping + metadata, read by the @tool map_generator.gd.

const BASE_COLOR := Color("#343d46")

## adm1_pcode -> macro-region id. Verified against .local/philippines_optimized.json.
const GROUPS := {
	"PH01": "NorthernLuzon", "PH02": "NorthernLuzon", "PH14": "NorthernLuzon",
	"PH03": "CentralLuzon", "PH13": "CentralLuzon",
	"PH04": "SouthernLuzon", "PH17": "SouthernLuzon", "PH05": "SouthernLuzon",
	"PH06": "Visayas", "PH07": "Visayas", "PH08": "Visayas",
	"PH09": "Mindanao", "PH10": "Mindanao", "PH11": "Mindanao",
	"PH12": "Mindanao", "PH16": "Mindanao", "PH19": "Mindanao",
}

## macro-region id -> display name, stage StageData resource, hover neon color.
const REGIONS := {
	"NorthernLuzon": {"display": "Northern Luzon",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres",
		"neon": Color("#ffd700")},
	"CentralLuzon": {"display": "Central Luzon",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres",
		"neon": Color("#8a2be2")},
	"SouthernLuzon": {"display": "Southern Luzon",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres",
		"neon": Color("#ff2d55")},
	"Visayas": {"display": "Visayas",
		"stage": "res://stages/beach_court/beach_court_data.tres",
		"neon": Color("#00e5ff")},
	"Mindanao": {"display": "Mindanao",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres",
		"neon": Color("#39ff14")},
}

signal region_selected(region_name: String, stage_name: String)

const HOVER_LIFT := -15.0
const HOVER_OUTLINE := 12.0

@export var label_path: NodePath

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_connect_regions()

func _connect_regions() -> void:
	for gid in REGIONS:
		var area := get_node_or_null(NodePath(gid)) as Area2D
		if area == null:
			continue
		area.input_pickable = true
		if not area.mouse_entered.is_connected(_on_hover_in):
			area.mouse_entered.connect(_on_hover_in.bind(area))
			area.mouse_exited.connect(_on_hover_out.bind(area))
			area.input_event.connect(_on_region_input.bind(area))

func _visual_of(area: Area2D) -> Node2D:
	return area.get_node_or_null("Visual") as Node2D

func _on_hover_in(area: Area2D) -> void:
	var gid := String(area.name)
	var visual := _visual_of(area)
	if visual == null:
		return
	area.z_index = 1
	var neon: Color = REGIONS[gid]["neon"]
	for child in visual.get_children():
		if child is Polygon2D:
			child.color = neon
		elif child is Line2D:
			child.width = HOVER_OUTLINE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", HOVER_LIFT, 0.35)
	_set_label(REGIONS[gid]["display"])

func _on_hover_out(area: Area2D) -> void:
	var visual := _visual_of(area)
	if visual == null:
		return
	area.z_index = 0
	for child in visual.get_children():
		if child is Polygon2D:
			child.color = BASE_COLOR
		elif child is Line2D:
			child.width = 6.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", 0.0, 0.35)
	_set_label("")

func _on_region_input(_viewport: Node, event: InputEvent, _shape_idx: int, area: Area2D) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(area)

func _select(area: Area2D) -> void:
	var gid := String(area.name)
	var display: String = REGIONS[gid]["display"]
	var stage_path: String = REGIONS[gid]["stage"]
	region_selected.emit(display, stage_path)
	# Autoload access under --script mode: bare identifier is unavailable.
	var main_loop: SceneTree = get_tree()
	var ms: Node = main_loop.root.get_node_or_null("MatchSelection") if main_loop else null
	if ms and ResourceLoader.exists(stage_path):
		ms.stage_data = load(stage_path)
	# Guard scene switch so headless --script tests don't navigate away.
	if not Engine.is_editor_hint() and main_loop and main_loop.current_scene != null:
		main_loop.change_scene_to_file("res://scenes/loading_screen.tscn")

func _set_label(text: String) -> void:
	if label_path.is_empty():
		return
	var lbl := get_node_or_null(label_path)
	if lbl and lbl is Label:
		lbl.text = text
