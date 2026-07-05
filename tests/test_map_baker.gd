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

	# exactly 5 region Node2Ds, named by macro-region id
	var region_names := {}
	for c in root.get_children():
		if Data.REGIONS.has(String(c.name)):
			region_names[String(c.name)] = c
	ok(region_names.size() == 5, "5 region nodes baked (got %d)" % region_names.size())
	for gid in Data.REGIONS:
		ok(region_names.has(gid), "region baked: " + gid)

	# each region: Visual/{Shadow,Underside,Top}; Top has >=1 Polygon2D + >=1 Line2D;
	# NO CollisionPolygon2D anywhere; region has a "centroid" metadata Vector2.
	for gid in region_names:
		var region: Node2D = region_names[gid]
		var visual := region.get_node_or_null("Visual")
		ok(visual != null, gid + " has Visual node")
		var top := region.get_node_or_null("Visual/Top")
		var underside := region.get_node_or_null("Visual/Underside")
		var shadow := region.get_node_or_null("Visual/Shadow")
		ok(top != null, gid + " has Visual/Top")
		ok(underside != null, gid + " has Visual/Underside")
		ok(shadow != null, gid + " has Visual/Shadow")
		var top_polys := 0
		var top_lines := 0
		if top:
			for v in top.get_children():
				if v is Polygon2D: top_polys += 1
				elif v is Line2D: top_lines += 1
		ok(top_polys >= 1, gid + " Top has >=1 Polygon2D (got %d)" % top_polys)
		ok(top_lines >= 1, gid + " Top has >=1 Line2D (got %d)" % top_lines)
		var cols := 0
		for a in region.get_children():
			if a is CollisionPolygon2D: cols += 1
		ok(cols == 0, gid + " has no CollisionPolygon2D")
		ok(region.has_meta("centroid"), gid + " stores centroid meta")
		if region.has_meta("centroid"):
			ok(region.get_meta("centroid") is Vector2, gid + " centroid is Vector2")

	# top-face fill uses the region's own base color
	var vis_region: Node2D = region_names["Visayas"]
	var vis_top: Node2D = vis_region.get_node("Visual/Top")
	var poly0: Polygon2D = null
	for v in vis_top.get_children():
		if v is Polygon2D:
			poly0 = v
			break
	ok(poly0 != null and poly0.color == Data.REGIONS["Visayas"]["base"],
		"Visayas top face uses its base color")

	# clear() removes them (idempotent)
	root.clear()
	var remaining := 0
	for c in root.get_children():
		if Data.REGIONS.has(String(c.name)): remaining += 1
	ok(remaining == 0, "clear() frees region nodes")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
