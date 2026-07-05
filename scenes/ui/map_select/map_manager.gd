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
const BASE_OUTLINE := 2.0   # thin resting stroke (matches generator OUTLINE_WIDTH)
const HOVER_OUTLINE := 4.0  # modest thickening on hover

@export var label_path: NodePath

var _hovered: Node2D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_unhandled_input(true)

## The 5 baked region roots (plain Node2D, named by macro-region id).
func _regions() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for gid in REGIONS:
		var r := get_node_or_null(NodePath(gid)) as Node2D
		if r != null:
			out.append(r)
	return out

func _visual_of(region: Node2D) -> Node2D:
	return region.get_node_or_null("Visual") as Node2D

## First region whose fill polygons contain global_pos. Tested in region-local
## space so the animated hover lift (Visual.position.y) doesn't shift the hit area.
func _region_at(global_pos: Vector2) -> Node2D:
	for region in _regions():
		var visual := _visual_of(region)
		if visual == null:
			continue
		var local := region.to_local(global_pos)
		for child in visual.get_children():
			if child is Polygon2D and Geometry2D.is_point_in_polygon(local, child.polygon):
				return region
	return null

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		_update_hover(get_global_mouse_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var region := _region_at(get_global_mouse_position())
		if region != null:
			_select(region)

func _update_hover(global_pos: Vector2) -> void:
	var region := _region_at(global_pos)
	if region == _hovered:
		return
	if _hovered != null:
		_apply_hover_out(_hovered)
	_hovered = region
	if _hovered != null:
		_apply_hover_in(_hovered)

func _apply_hover_in(region: Node2D) -> void:
	var gid := String(region.name)
	var visual := _visual_of(region)
	if visual == null:
		return
	region.z_index = 1
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

func _apply_hover_out(region: Node2D) -> void:
	var visual := _visual_of(region)
	if visual == null:
		return
	region.z_index = 0
	for child in visual.get_children():
		if child is Polygon2D:
			child.color = BASE_COLOR
		elif child is Line2D:
			child.width = BASE_OUTLINE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", 0.0, 0.35)
	_set_label("")

func _select(region: Node2D) -> void:
	var gid := String(region.name)
	var display: String = REGIONS[gid]["display"]
	var stage_path: String = REGIONS[gid]["stage"]
	region_selected.emit(display, stage_path)
	# Autoload reached via the tree root: the bare identifier is unavailable in --script mode.
	var main_loop: SceneTree = get_tree() if is_inside_tree() else null
	var ms: Node = main_loop.root.get_node_or_null("MatchSelection") if main_loop else null
	if ms and ResourceLoader.exists(stage_path):
		ms.stage_data = load(stage_path)
	# 7.5 — training enters this flow from the TRAINING menu item (character
	# select → map select): cut straight to the training scene, skipping the
	# loading-screen → intro → match pipeline. Otherwise start the match.
	var next_scene := "res://scenes/loading_screen.tscn"
	if ms and ms.training:
		next_scene = "res://scenes/training.tscn"
	# Guard scene switch so headless --script tests don't navigate away.
	if not Engine.is_editor_hint() and main_loop and main_loop.current_scene != null:
		main_loop.change_scene_to_file(next_scene)

func _set_label(text: String) -> void:
	if label_path.is_empty():
		return
	var lbl := get_node_or_null(label_path)
	if lbl and lbl is Label:
		lbl.text = text
