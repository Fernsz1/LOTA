extends Node2D
## Upright beacons + light beams at each region's projected centroid. Lives in flat
## screen space (z 30) between the tilted map and the overlay UI, so the beams stand
## upright with no counter-rotation. Colors track hover/select via set_color.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")
const INK := Color("#0a0904")

@export var map_plane_path: NodePath

## Screen-space nudges to pull overlapping beacons apart. Northern & Central Luzon
## share almost the same X column, so their upright beams sit on top of each other —
## push them to opposite sides.
const NUDGE := {
	"NorthernLuzon": Vector2(-38.0, 0.0),
	"CentralLuzon": Vector2(38.0, 0.0),
}

var _colors := {}   # gid -> Color

func _ready() -> void:
	z_index = 30
	if get_child_count() == 0 and not map_plane_path.is_empty():
		_auto_build()

## Build from region centroids projected through the MapPlane transform.
func _auto_build() -> void:
	var plane := get_node_or_null(map_plane_path) as Node2D
	if plane == null:
		return
	var entries := []
	for gid in Data.REGION_ORDER:
		var region := plane.get_node_or_null(NodePath(gid)) as Node2D
		if region == null or not region.has_meta("centroid"):
			continue
		var centroid: Vector2 = region.get_meta("centroid")
		var pos: Vector2 = plane.transform * centroid + NUDGE.get(gid, Vector2.ZERO)
		entries.append({"gid": gid, "pos": pos, "color": Data.REGIONS[gid]["base"]})
	build(entries)

func build(entries: Array) -> void:
	for c in get_children():
		c.free()
	_colors.clear()
	for e in entries:
		var gid: String = e["gid"]
		_colors[gid] = e["color"]
		var beacon := Node2D.new()
		beacon.name = gid
		beacon.position = e["pos"]
		add_child(beacon)
		beacon.set_meta("gid", gid)
		beacon.draw.connect(_draw_beacon.bind(beacon))
		_pulse(beacon)

func set_color(gid: String, color: Color) -> void:
	if not _colors.has(gid):
		return
	_colors[gid] = color
	var beacon := get_node_or_null(NodePath(gid))
	if beacon:
		beacon.queue_redraw()

func marker_color(gid: String) -> Color:
	return _colors.get(gid, Color.WHITE)

## Gentle infinite pulse on the beacon's scale (beamPulse/corePulse feel).
func _pulse(beacon: Node2D) -> void:
	if not is_inside_tree():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(beacon, "scale", Vector2(1.12, 1.12), 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(beacon, "scale", Vector2(1.0, 1.0), 1.1).set_trans(Tween.TRANS_SINE)

func _draw_beacon(beacon: Node2D) -> void:
	var col: Color = _colors.get(String(beacon.name), Color.WHITE)
	# upright light beam: a soft vertical cone rising from the beacon
	var beam := PackedVector2Array([
		Vector2(-3, 0), Vector2(3, 0), Vector2(16, -104), Vector2(-16, -104)])
	beacon.draw_colored_polygon(beam, Color(col.r, col.g, col.b, 0.22))
	var core_beam := PackedVector2Array([
		Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(5, -98), Vector2(-5, -98)])
	beacon.draw_colored_polygon(core_beam, Color(col.r, col.g, col.b, 0.5))
	# pulsing halo
	beacon.draw_circle(Vector2.ZERO, 22.0, Color(col.r, col.g, col.b, 0.25))
	# core dot with ink ring
	beacon.draw_circle(Vector2.ZERO, 9.5, INK)
	beacon.draw_circle(Vector2.ZERO, 7.0, col)
