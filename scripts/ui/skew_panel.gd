@tool
class_name SkewPanel
extends Control
## Graphic-novel panel: a slightly skewed parallelogram with a hard black offset
## shadow, solid fill, thick border, and an optional accent header strip. Cel-shaded
## look for map-select chrome (header / tooltip / confirm hub). Purely cosmetic;
## place text/controls as children on top.

@export var skew_px: float = 14.0:
	set(v): skew_px = v; queue_redraw()
@export var fill_color: Color = Color("14101d"):
	set(v): fill_color = v; queue_redraw()
@export var border_color: Color = Color.BLACK:
	set(v): border_color = v; queue_redraw()
@export var shadow_color: Color = Color(0, 0, 0, 0.55):
	set(v): shadow_color = v; queue_redraw()
@export var shadow_offset: Vector2 = Vector2(8, 8):
	set(v): shadow_offset = v; queue_redraw()
@export var border_width: float = 4.0:
	set(v): border_width = v; queue_redraw()
@export var accent_color: Color = Color(0, 0, 0, 0):
	set(v): accent_color = v; queue_redraw()
@export var header_height: float = 0.0:
	set(v): header_height = v; queue_redraw()


func _points() -> PackedVector2Array:
	var s := size
	# top edge shifted right by skew_px -> left-leaning parallelogram
	return PackedVector2Array([
		Vector2(skew_px, 0.0),
		Vector2(s.x, 0.0),
		Vector2(s.x - skew_px, s.y),
		Vector2(0.0, s.y),
	])


func _draw() -> void:
	var pts := _points()
	var shadow := PackedVector2Array()
	for p: Vector2 in pts:
		shadow.append(p + shadow_offset)
	draw_colored_polygon(shadow, shadow_color)
	draw_colored_polygon(pts, fill_color)
	if header_height > 0.0 and accent_color.a > 0.0:
		var hy := header_height
		var head := PackedVector2Array([
			pts[0], pts[1],
			Vector2(pts[1].x - skew_px * (hy / size.y), hy),
			Vector2(pts[0].x - skew_px * (hy / size.y), hy),
		])
		draw_colored_polygon(head, accent_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, border_width)
