extends SceneTree

const Gen := preload("res://scenes/ui/map_select/map_generator.gd")
const Mgr := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0
var emitted := []

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _on_selected(name: String, stage: String) -> void:
	emitted.append([name, stage])

## A point guaranteed inside the polygon: centroid if it lands inside, else a
## bounding-box grid sample. Returns null if none found (untyped -> may be null).
func _interior_point(poly: Polygon2D):
	var pts := poly.polygon
	if pts.size() < 3:
		return null
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	if Geometry2D.is_point_in_polygon(c, pts):
		return c
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var steps := 24
	for i in range(1, steps):
		for j in range(1, steps):
			var s := Vector2(lerpf(lo.x, hi.x, float(i) / steps),
				lerpf(lo.y, hi.y, float(j) / steps))
			if Geometry2D.is_point_in_polygon(s, pts):
				return s
	return null

func _init() -> void:
	if not FileAccess.file_exists(Gen.SOURCE):
		print("SKIP: source GeoJSON missing")
		print("%d checks, %d failures" % [checks, failures])
		quit(0)
		return
	# Build regions under a tilted MapPlane, then run the manager against it.
	var root: Node2D = Mgr.new()
	get_root().add_child(root)
	var plane := Node2D.new()
	plane.name = "MapPlane"
	root.add_child(plane)
	root.map_plane_path = NodePath("MapPlane")
	# bake region Node2Ds as children of the plane
	var gen: Node2D = Gen.new()
	root.add_child(gen)
	gen.build_into(plane)
	gen.free()
	# apply the affine tilt about the archipelago centre
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in root._regions():
		var c: Vector2 = r.get_meta("centroid")
		lo = lo.min(c); hi = hi.max(c)
	var centre := (lo + hi) * 0.5
	plane.transform = Mgr.tilt_transform(centre, Mgr.TILT_ROT_DEG, Mgr.TILT_SCALE_Y)

	var region: Node2D = plane.get_node("Visayas")
	var visual: Node2D = region.get_node("Visual")

	# an interior point of a Top polygon, taken through the tilt, resolves to the region
	var top: Node2D = region.get_node("Visual/Top")
	var poly: Polygon2D = null
	for v in top.get_children():
		if v is Polygon2D:
			poly = v
			break
	ok(poly != null, "Visayas has a Top polygon")

	ok(root._region_at(Vector2(-5000, -5000)) == null, "_region_at outside map returns null")
	var inside = _interior_point(poly)  # untyped: may be null (plane-space point)
	ok(inside != null, "found an interior sample point in Visayas")
	if inside != null:
		# poly points are in plane space; map plane-space -> global for the query
		var global_pt: Vector2 = plane.to_global(inside)
		ok(root._region_at(global_pt) == region, "_region_at interior point (through tilt) -> Visayas")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
