@tool
extends Node2D
## Edit-time baker for the Map Select screen. Reads the raw GeoJSON, projects
## lon/lat into a 1920x1080 design space, groups 17 admin regions into 5 macro-
## regions, and bakes persistent Area2D/Polygon2D/Line2D/CollisionPolygon2D nodes.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")

## Exterior ring (index 0) of every polygon; handles Polygon and MultiPolygon.
static func exterior_rings(geom: Dictionary) -> Array:
	var polys: Array = []
	if geom["type"] == "Polygon":
		polys = [geom["coordinates"]]
	else: # MultiPolygon
		polys = geom["coordinates"]
	var rings: Array = []
	for poly in polys:
		if poly.size() > 0:
			rings.append(poly[0])
	return rings

## {lon_min, lat_max, scale, offset} for a uniform, centered, Y-flipped fit.
static func compute_bounds(features: Array, view: Vector2, pad: float) -> Dictionary:
	var lon_min := INF
	var lon_max := -INF
	var lat_min := INF
	var lat_max := -INF
	for f in features:
		for ring in exterior_rings(f["geometry"]):
			for pt in ring:
				lon_min = min(lon_min, pt[0])
				lon_max = max(lon_max, pt[0])
				lat_min = min(lat_min, pt[1])
				lat_max = max(lat_max, pt[1])
	var lon_span: float = max(lon_max - lon_min, 0.000001)
	var lat_span: float = max(lat_max - lat_min, 0.000001)
	var scale: float = min((view.x - 2.0 * pad) / lon_span, (view.y - 2.0 * pad) / lat_span)
	# center the fitted map within the padded viewport
	var offset := Vector2(
		((view.x - 2.0 * pad) - lon_span * scale) * 0.5,
		((view.y - 2.0 * pad) - lat_span * scale) * 0.5)
	return {"lon_min": lon_min, "lat_max": lat_max, "scale": scale, "offset": offset,
		"pad": pad}

static func project(lon: float, lat: float, b: Dictionary) -> Vector2:
	return Vector2(
		b["pad"] + b["offset"].x + (lon - b["lon_min"]) * b["scale"],
		b["pad"] + b["offset"].y + (b["lat_max"] - lat) * b["scale"])

static func ring_to_points(ring: Array, b: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for pt in ring:
		pts.append(project(pt[0], pt[1], b))
	return pts

static func ring_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return abs(a) * 0.5
