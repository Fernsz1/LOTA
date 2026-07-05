extends Node2D
## Runtime controller for the Map Select screen (MapRoot). Also the single source
## of truth for region grouping + metadata, read by the @tool map_generator.gd.

## Shared ink + underside tokens (also read by the @tool generator).
const INK := Color("#0a0904")
const UNDERSIDE := Color("#2a2612")

## adm1_pcode -> macro-region id. Verified against .local/philippines_optimized.json.
const GROUPS := {
	"PH01": "NorthernLuzon", "PH02": "NorthernLuzon", "PH14": "NorthernLuzon",
	"PH03": "CentralLuzon", "PH13": "CentralLuzon",
	"PH04": "SouthernLuzon", "PH17": "SouthernLuzon", "PH05": "SouthernLuzon",
	"PH06": "Visayas", "PH07": "Visayas", "PH08": "Visayas",
	"PH09": "Mindanao", "PH10": "Mindanao", "PH11": "Mindanao",
	"PH12": "Mindanao", "PH16": "Mindanao", "PH19": "Mindanao",
}

## macro-region id -> full hi-fi metadata. THE single source of truth (generator,
## UI, and markers all read this). Stage mapping matches the handoff table exactly.
const REGIONS := {
	"NorthernLuzon": {
		"index": 1, "display": "NORTHERN LUZON",
		"base": Color("#3f6f92"), "neon": Color("#34b0ff"), "neon_stroke": Color("#bfe6ff"),
		"fighter": "BUNO",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres",
		"stage_label": "MOUNTAIN FESTIVAL GROUNDS",
		"story": "Highland grapplers forged in the festivals of the Cordillera ranges."},
	"CentralLuzon": {
		"index": 2, "display": "CENTRAL LUZON",
		"base": Color("#a8432f"), "neon": Color("#ff5a3c"), "neon_stroke": Color("#ffc7ba"),
		"fighter": "DIRTY BOXING",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres",
		"stage_label": "BARANGAY BOXING RING",
		"story": "Street-hardened brawlers trading blows in the barangay rings."},
	"SouthernLuzon": {
		"index": 3, "display": "SOUTHERN LUZON",
		"base": Color("#5c8038"), "neon": Color("#84e23c"), "neon_stroke": Color("#d9ffb2"),
		"fighter": "ARNIS",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres",
		"stage_label": "BAHAY KUBO TRAINING YARD",
		"story": "Stick-and-blade masters drilling in the southern training yards."},
	"Visayas": {
		"index": 4, "display": "VISAYAS",
		"base": Color("#6b4a9c"), "neon": Color("#b154ff"), "neon_stroke": Color("#e2c2ff"),
		"fighter": "SIKARAN",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres",
		"stage_label": "HERITAGE PLAZA",
		"story": "Sikaran was born from freedom and resilience in the island heartland."},
	"Mindanao": {
		"index": 5, "display": "MINDANAO",
		"base": Color("#c0982f"), "neon": Color("#ffd23a"), "neon_stroke": Color("#fff1b0"),
		"fighter": "SEPAK TAKRAW",
		"stage": "res://stages/beach_court/beach_court_data.tres",
		"stage_label": "BEACH COURT AT DUSK",
		"story": "Airborne acrobats who settle every score on the dusk-lit shore."},
}

## Region ids in index order (1..5) — stable iteration + labeling.
const REGION_ORDER: Array[String] = [
	"NorthernLuzon", "CentralLuzon", "SouthernLuzon", "Visayas", "Mindanao"]

signal region_selected(region_name: String, stage_name: String)

const HOVER_LIFT := -15.0
const TOP_STROKE := 7.0
const HOVER_FILL := Color("#a7a24b")
const HOVER_STROKE := Color("#ffd24a")
const HOVER_ACCENT := Color("#ffcf3f")
const IDLE_ACCENT := Color("#4a5058")

## Static affine tilt (comic-book diagonal + faked elevation). No 3D.
const TILT_ROT_DEG := -20.0
const TILT_SCALE_Y := 0.6560590   # cos(49°)

@export var map_plane_path: NodePath
@export var ui_path: NodePath
@export var markers_path: NodePath

var _hovered: Node2D = null
var _selected: Node2D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_unhandled_input(true)
	var ui := _ui()
	if ui and ui.has_signal("confirm_pressed"):
		ui.confirm_pressed.connect(confirm)
	_push_ui(null)  # STANDBY

func _ui() -> Node:
	return get_node_or_null(ui_path) if not ui_path.is_empty() else null

func _markers() -> Node:
	return get_node_or_null(markers_path) if not markers_path.is_empty() else null

## T(p) = centre + R(rot) * S(1, scale_y) * (p - centre). Squash first, then rotate.
static func tilt_transform(centre: Vector2, rot_deg: float, scale_y: float) -> Transform2D:
	var pivot_in := Transform2D(0.0, -centre)
	var squash := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, scale_y), Vector2.ZERO)
	var rot := Transform2D(deg_to_rad(rot_deg), Vector2.ZERO)
	var pivot_out := Transform2D(0.0, centre)
	return pivot_out * rot * squash * pivot_in

## Node holding the tilted region children (falls back to self for flat trees).
func _plane() -> Node:
	if not map_plane_path.is_empty():
		var p := get_node_or_null(map_plane_path)
		if p != null:
			return p
	return self

## The 5 baked region roots (plain Node2D, named by macro-region id).
func _regions() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var plane := _plane()
	for gid in REGIONS:
		var r := plane.get_node_or_null(NodePath(gid)) as Node2D
		if r != null:
			out.append(r)
	return out

func _top_of(region: Node2D) -> Node2D:
	return region.get_node_or_null("Visual/Top") as Node2D

func _visual_of(region: Node2D) -> Node2D:
	return region.get_node_or_null("Visual") as Node2D

## First region whose Top-face polygons contain global_pos. Tested in region-local
## space (which includes the MapPlane tilt via to_local), so neither the tilt nor
## the hover lift shifts the hit area.
func _region_at(global_pos: Vector2) -> Node2D:
	for region in _regions():
		var top := _top_of(region)
		if top == null:
			continue
		var local := region.to_local(global_pos)
		for child in top.get_children():
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
	else:
		_push_ui(_selected)  # fall back to selected (or STANDBY)

## Paint a region's Top face + its marker. `state` in {"base","hover","select"}.
func _paint(region: Node2D, state: String) -> void:
	var top := _top_of(region)
	if top == null:
		return
	var gid := String(region.name)
	var meta: Dictionary = REGIONS[gid]
	var fill: Color
	var stroke: Color
	match state:
		"hover":
			fill = HOVER_FILL; stroke = HOVER_STROKE
		"select":
			fill = meta["neon"]; stroke = meta["neon_stroke"]
		_:
			fill = meta["base"]; stroke = INK
	for child in top.get_children():
		if child is Polygon2D:
			child.color = fill
		elif child is Line2D:
			child.default_color = stroke
	var markers := _markers()
	if markers and markers.has_method("set_color"):
		var dot: Color = HOVER_STROKE if state == "hover" else \
			(meta["neon"] if state == "select" else meta["base"])
		markers.set_color(gid, dot)

func _apply_hover_in(region: Node2D) -> void:
	_hovered = region
	region.z_index = 1
	_paint(region, "hover")
	var visual := _visual_of(region)
	if visual:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position:y", HOVER_LIFT, 0.22)
	_push_ui(region)

func _apply_hover_out(region: Node2D) -> void:
	region.z_index = 0
	_paint(region, "select" if region == _selected else "base")
	var visual := _visual_of(region)
	if visual:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position:y", 0.0, 0.22)

func _select(region: Node2D) -> void:
	if _selected != null and _selected != region:
		_paint(_selected, "base")
	_selected = region
	_paint(region, "select")
	_push_ui(region)

## Build the UI state dict for the region driving the panel (hovered has priority;
## else selected; else STANDBY when null).
func _push_ui(region: Node2D) -> void:
	var ui := _ui()
	if ui == null or not ui.has_method("set_state"):
		return
	var hovering := _hovered != null
	var d := {}
	if region == null:
		d = {"kicker": "STANDBY", "accent": IDLE_ACCENT, "region_name": "SELECT YOUR ARENA",
			"region_no": "", "fighter": "—", "stage": "—",
			"story": "Hover a region to scout its stage and fighter. Click a landmass to lock your pick, then confirm.",
			"fighter_label": _selected_fighter(), "confirm_enabled": _selected != null}
	else:
		var gid := String(region.name)
		var m: Dictionary = REGIONS[gid]
		var accent: Color = HOVER_ACCENT if hovering else m["neon"]
		var kicker := "HOVER · SCOUTING" if hovering else "LOCKED IN"
		d = {"kicker": kicker, "accent": accent, "region_name": m["display"],
			"region_no": "(REGION %d)" % m["index"], "fighter": m["fighter"],
			"stage": m["stage_label"], "story": m["story"],
			"fighter_label": _selected_fighter(), "confirm_enabled": _selected != null}
	ui.set_state(d)

func _selected_fighter() -> String:
	if _selected == null:
		return ""  # header hides the FIGHTER line until a real pick is locked in
	return REGIONS[String(_selected.name)]["fighter"]

## Commit the current selection: show the ribbon, emit, stash stage, navigate.
func confirm() -> void:
	if _selected == null:
		return
	var gid := String(_selected.name)
	var meta: Dictionary = REGIONS[gid]
	var stage_path: String = meta["stage"]
	region_selected.emit(meta["display"], stage_path)
	var ui := _ui()
	if ui and ui.has_method("show_ribbon"):
		ui.show_ribbon(meta["stage_label"])
	var tree := get_tree() if is_inside_tree() else null
	var ms: Node = tree.root.get_node_or_null("MatchSelection") if tree else null
	if ms and ResourceLoader.exists(stage_path):
		ms.stage_data = load(stage_path)
	# Delay navigation so the ribbon plays (~1.55s), then hand off to the existing flow.
	if not Engine.is_editor_hint() and tree and tree.current_scene != null:
		var next_scene := "res://scenes/loading_screen.tscn"
		if ms and ms.training:
			next_scene = "res://scenes/training.tscn"
		await tree.create_timer(1.55).timeout
		if is_inside_tree() and tree.current_scene != null:
			tree.change_scene_to_file(next_scene)
