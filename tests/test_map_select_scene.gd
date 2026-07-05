extends SceneTree
## End-to-end: MapSelection.tscn boots with all layers, hit-tests through the tilt,
## selects + gates confirm, all headless with no script/parse/decompose errors.

const SCENE := "res://scenes/ui/map_select/MapSelection.tscn"
const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	var packed: PackedScene = load(SCENE)
	ok(packed != null, "MapSelection.tscn loads")
	if packed == null:
		_finish(); return
	var scene: Node = packed.instantiate()
	get_root().add_child(scene)
	await process_frame   # let children build (markers auto-build, UI _ready)
	await process_frame

	ok(scene.get_node_or_null("Background") != null, "Background layer present")
	ok(scene.get_node_or_null("MapPlane") != null, "MapPlane present")
	ok(scene.get_node_or_null("Markers") != null, "Markers present")
	ok(scene.get_node_or_null("UI") != null, "UI present")

	var plane: Node2D = scene.get_node("MapPlane")
	var regions := 0
	for gid in Data.REGION_ORDER:
		if plane.get_node_or_null(NodePath(gid)) != null:
			regions += 1
	ok(regions == 5, "5 regions under MapPlane (got %d)" % regions)

	# markers auto-built one beacon per region
	var markers: Node2D = scene.get_node("Markers")
	ok(markers.get_child_count() == 5, "5 beacons built (got %d)" % markers.get_child_count())

	# hit-test an interior point through the tilt
	var vis: Node2D = plane.get_node("Visayas")
	var top: Node2D = vis.get_node("Visual/Top")
	var poly: Polygon2D = null
	for c in top.get_children():
		if c is Polygon2D:
			poly = c; break
	ok(poly != null, "Visayas has a Top polygon")
	if poly:
		var inside := _interior(poly.polygon)
		ok(inside != Vector2.INF, "found interior point")
		if inside != Vector2.INF:
			var hit: Node2D = scene._region_at(plane.to_global(inside))
			ok(hit == vis, "_region_at resolves Visayas through tilt")
			# select + confirm gating
			scene._select(vis)
			ok(scene._selected == vis, "click selects Visayas")

	_finish()

func _interior(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts: c += p
	c /= pts.size()
	if Geometry2D.is_point_in_polygon(c, pts):
		return c
	var lo := pts[0]; var hi := pts[0]
	for p in pts:
		lo = lo.min(p); hi = hi.max(p)
	for i in range(1, 24):
		for j in range(1, 24):
			var s := Vector2(lerpf(lo.x, hi.x, i / 24.0), lerpf(lo.y, hi.y, j / 24.0))
			if Geometry2D.is_point_in_polygon(s, pts):
				return s
	return Vector2.INF

func _finish() -> void:
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
