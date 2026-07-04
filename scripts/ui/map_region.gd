@tool
class_name MapRegion
extends Node2D
## One clickable Philippines region on the map-select screen. Built from a baked
## region dict (data/map_regions.json) at runtime and, via the @tool parent, in the
## editor. Fill = Polygon2D per ring; outline = black Line2D; accent glow = wider
## Line2D shown when active. Hit-testing is point-in-polygon (see contains_point) —
## no Area2D, so the concave archipelago rings never hit Godot's physics convex
## decomposition (which fails on them). Hover/selected lifts the whole node uniformly.

const LIFT_PX := 16.0
const REST_FILL := Color("63552f")
const OUTLINE_W := 4.0
const GLOW_W := 10.0

var region_id: int = 0
var accent: Color = Color.WHITE

var _fills: Array[Polygon2D] = []
var _glows: Array[Line2D] = []
var _rings: Array[PackedVector2Array] = []
var _base_y: float = 0.0
var _tween: Tween


func setup(data: Dictionary) -> void:
	region_id = int(data["id"])
	accent = Color(str(data["accent_color"]))
	var rings: Array = data["outline_polygons"]
	var bangers := load("res://art/fonts/Bangers-Regular.ttf")

	for ring: Array in rings:
		var pts := _to_points(ring)
		_rings.append(pts)

		var glow := Line2D.new()
		glow.points = _closed(pts)
		glow.width = GLOW_W
		glow.default_color = accent
		glow.joint_mode = Line2D.LINE_JOINT_ROUND
		glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		glow.end_cap_mode = Line2D.LINE_CAP_ROUND
		glow.visible = false
		glow.z_index = -1
		add_child(glow)
		_glows.append(glow)

		var fill := Polygon2D.new()
		fill.polygon = pts
		fill.color = REST_FILL
		add_child(fill)
		_fills.append(fill)

		var outline := Line2D.new()
		outline.points = _closed(pts)
		outline.width = OUTLINE_W
		outline.default_color = Color.BLACK
		outline.joint_mode = Line2D.LINE_JOINT_ROUND
		outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
		outline.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(outline)

	var label := Label.new()
	label.text = str(data["display_name"]).to_upper()
	label.add_theme_font_override("font", bangers)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var anchor: Array = data["label_anchor"]
	label.position = Vector2(float(anchor[0]) - 60.0, float(anchor[1]) - 12.0)
	label.custom_minimum_size = Vector2(120, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _to_points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < flat.size() - 1:
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
		i += 2
	return out


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var c := pts.duplicate()
	if pts.size() > 0:
		c.append(pts[0])
	return c


func contains_point(p: Vector2) -> bool:
	## p is in the parent (MapContainer) space; the rings are authored in that space
	## and this node's base offset is (0, 0), so test directly. Tests against the
	## resting geometry (ignores the active lift) so the hit area doesn't shift as the
	## region rises. Union over rings: inside if within any ring (rings are separate
	## islands, not holes).
	for ring: PackedVector2Array in _rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


func set_active(active: bool) -> void:
	for g: Line2D in _glows:
		g.visible = active
	var target_fill := accent.darkened(0.45) if active else REST_FILL
	for f: Polygon2D in _fills:
		f.color = target_fill
	z_index = 1 if active else 0
	var target_y := _base_y - LIFT_PX if active else _base_y
	if Engine.is_editor_hint():
		position.y = target_y
		return
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.tween_property(self, "position:y", target_y, 0.15)


func set_base_y(y: float) -> void:
	_base_y = y
	position.y = y
