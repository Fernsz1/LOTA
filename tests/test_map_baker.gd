extends SceneTree

const Gen := preload("res://scenes/ui/map_select/map_generator.gd")
const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	if not FileAccess.file_exists(Gen.SOURCE):
		print("SKIP: source GeoJSON missing at ", Gen.SOURCE)
		print("%d checks, %d failures" % [checks, failures])
		quit(0)
		return
	var root: Node2D = Gen.new()
	get_root().add_child(root)
	root.build()

	# exactly 5 region Area2Ds, named by macro-region id
	var area_names := {}
	for c in root.get_children():
		if c is Area2D:
			area_names[c.name] = c
	ok(area_names.size() == 5, "5 Area2D regions baked (got %d)" % area_names.size())
	for gid in Data.REGIONS:
		ok(area_names.has(gid), "region baked: " + gid)

	# each region has a Visual node + >=1 Polygon2D + >=1 Line2D + >=1 CollisionPolygon2D
	for gid in area_names:
		var area: Area2D = area_names[gid]
		var visual := area.get_node_or_null("Visual")
		ok(visual != null, gid + " has Visual node")
		var polys := 0
		var lines := 0
		var cols := 0
		if visual:
			for v in visual.get_children():
				if v is Polygon2D: polys += 1
				elif v is Line2D: lines += 1
		for a in area.get_children():
			if a is CollisionPolygon2D: cols += 1
		ok(polys >= 1, gid + " has >=1 Polygon2D (got %d)" % polys)
		ok(lines >= 1, gid + " has >=1 Line2D (got %d)" % lines)
		ok(cols >= 1, gid + " has >=1 CollisionPolygon2D (got %d)" % cols)

	# base fill color applied
	var first: Area2D = area_names[area_names.keys()[0]]
	var poly0: Polygon2D = null
	for v in first.get_node("Visual").get_children():
		if v is Polygon2D:
			poly0 = v
			break
	ok(poly0 != null and poly0.color == Data.BASE_COLOR, "base slate fill applied")

	# clear() removes them (idempotent)
	root.clear()
	var remaining := 0
	for c in root.get_children():
		if c is Area2D: remaining += 1
	ok(remaining == 0, "clear() frees region Area2Ds")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
