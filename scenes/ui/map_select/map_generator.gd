@tool
extends Node2D
## Edit-time baker for the Map Select screen. Reads the raw GeoJSON, projects
## lon/lat into a 1280x720 design space, groups 17 admin regions into 5 macro-
## regions, and bakes persistent Node2D/Polygon2D/Line2D nodes (hit-testing is
## geometric at runtime — no Area2D/CollisionPolygon2D).

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

## Perpendicular distance from p to the segment a-b (or to a if a==b).
static func _perp_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0000001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Ramer-Douglas-Peucker polyline simplification (iterative — safe for huge rings).
## Reduces vertex count massively while preserving overall shape; drives down scene
## size and, critically, CollisionPolygon2D convex-decomposition cost at load.
static func simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 4:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := seg.x
		var b := seg.y
		var dmax := 0.0
		var idx := -1
		for i in range(a + 1, b):
			var d := _perp_dist(pts[i], pts[a], pts[b])
			if d > dmax:
				dmax = d
				idx = i
		if dmax > eps and idx != -1:
			keep[idx] = 1
			stack.push_back(Vector2i(a, idx))
			stack.push_back(Vector2i(idx, b))
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(pts[i])
	return out

static func ring_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return abs(a) * 0.5

const SOURCE := "res://.local/philippines_optimized.json"
const VIEW := Vector2(1280, 720)  # match the project's canvas_items base viewport
const PAD := 60.0
const MIN_AREA := 8.0        # drop islets smaller than this (projected px^2)
const OUTLINE_WIDTH := 2.0   # thin graphic-novel stroke
const SIMPLIFY_EPS := 1.5    # Douglas-Peucker tolerance (projected px); higher = fewer verts
const OUTLINE_SHADER := "res://scenes/ui/map_select/outline.gdshader"

@export var build_map: bool = false:
	set(v):
		build_map = false
		if v:
			build()

@export var clear_map: bool = false:
	set(v):
		clear_map = false
		if v:
			clear()

func clear() -> void:
	_free_regions(self)

func build() -> void:
	build_into(self)

## Free previously baked region roots (matched by macro-region name, since they
## are plain Node2D). Immediate free so an editor re-bake doesn't double up.
func _free_regions(target: Node2D) -> void:
	for c in target.get_children():
		if Data.REGIONS.has(String(c.name)):
			c.free()

func build_into(target: Node2D) -> void:
	_free_regions(target)
	var txt := FileAccess.get_file_as_string(SOURCE)
	if txt.is_empty():
		push_error("Map source not found or empty: " + SOURCE)
		return
	var doc: Dictionary = JSON.parse_string(txt)
	var features: Array = doc["features"]
	var b := compute_bounds(features, VIEW, PAD)

	# collect projected exterior rings per macro-region
	var rings_by_region := {}
	for gid in Data.REGIONS:
		rings_by_region[gid] = []
	for f in features:
		var pcode: String = f["properties"]["adm1_pcode"]
		if not Data.GROUPS.has(pcode):
			continue
		var gid: String = Data.GROUPS[pcode]
		for ring in exterior_rings(f["geometry"]):
			var pts := ring_to_points(ring, b)
			if ring_area(pts) < MIN_AREA:
				continue
			pts = simplify(pts, SIMPLIFY_EPS)
			if pts.size() >= 3:
				rings_by_region[gid].append(pts)

	var tree := get_tree() if is_inside_tree() else null
	var owner_root: Node = tree.edited_scene_root if tree else null
	for gid in Data.REGIONS:
		_bake_region_into(target, gid, rings_by_region[gid], owner_root)

func _bake_region_into(target: Node2D, gid: String, rings: Array, owner_root: Node) -> void:
	# Region root is a plain Node2D — hit-testing is done at runtime with
	# Geometry2D.is_point_in_polygon (map_manager), avoiding CollisionPolygon2D
	# convex decomposition entirely (fails on self-touching coastline rings).
	var region := Node2D.new()
	region.name = gid
	target.add_child(region)
	if owner_root:
		region.set_owner(owner_root)

	var visual := Node2D.new()
	visual.name = "Visual"
	region.add_child(visual)
	if owner_root:
		visual.set_owner(owner_root)

	var shader: Shader = load(OUTLINE_SHADER) if ResourceLoader.exists(OUTLINE_SHADER) else null

	for pts in rings:
		# fill
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = Data.BASE_COLOR
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			poly.material = mat
		visual.add_child(poly)
		if owner_root:
			poly.set_owner(owner_root)
		# ink stroke
		var line := Line2D.new()
		var closed := PackedVector2Array(pts)
		if closed.size() > 0:
			closed.append(closed[0])
		line.points = closed
		line.width = OUTLINE_WIDTH
		line.default_color = Color.BLACK
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		visual.add_child(line)
		if owner_root:
			line.set_owner(owner_root)
