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
	# Build children with the generator, then attach a manager to a fresh MapRoot
	# by baking into a node that runs the manager script.
	var root: Node2D = Mgr.new()
	get_root().add_child(root)
	# synthesize baked region nodes using the generator, baked into `root`
	var gen: Node2D = Gen.new()
	root.add_child(gen)
	gen.build_into(root)   # bakes region Node2Ds as children of `root`
	gen.free()

	var region: Node2D = root.get_node("Visayas")
	var visual: Node2D = region.get_node("Visual")

	# hover in recolors to neon synchronously (only position.y is tweened)
	root._apply_hover_in(region)
	var neon: Color = Mgr.REGIONS["Visayas"]["neon"]
	var poly: Polygon2D = null
	for v in visual.get_children():
		if v is Polygon2D:
			poly = v
			break
	ok(poly != null and poly.color == neon, "hover recolors fill to neon")

	root._apply_hover_out(region)
	ok(poly.color == Mgr.BASE_COLOR, "hover-out reverts to base color")

	# point-in-polygon hit-testing: outside -> null; an interior point -> the region
	ok(root._region_at(Vector2(-5000, -5000)) == null, "_region_at outside map returns null")
	var inside = _interior_point(poly)  # untyped: may be null
	ok(inside != null, "found an interior sample point in Visayas")
	if inside != null:
		# poly points are in region-local space (Visual at rest); convert to global
		var inside_v: Vector2 = inside
		ok(root._region_at(region.to_global(inside_v)) == region, "_region_at interior point -> Visayas")

	# click/select emits region_selected with correct (name, stage)
	root.region_selected.connect(_on_selected)
	root._select(region)
	ok(emitted.size() >= 1, "region_selected emitted")
	if emitted.size() >= 1:
		ok(emitted[0][0] == "Visayas", "emitted name == Visayas")
		ok(emitted[0][1] == Mgr.REGIONS["Visayas"]["stage"], "emitted stage path correct")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
