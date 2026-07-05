extends SceneTree

const Mgr := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var path := "res://scenes/ui/map_select/MapSelection.tscn"
	ok(ResourceLoader.exists(path), "MapSelection.tscn exists")
	var ps: PackedScene = load(path)
	ok(ps != null, "scene loads")
	var scene: Node = ps.instantiate()
	get_root().add_child(scene)
	await process_frame  # let _ready/_connect_regions run

	# Region roots are plain Node2D (hit-testing is geometric point-in-polygon at
	# runtime — no Area2D / CollisionPolygon2D baked into the scene).
	var regions := {}
	for c in scene.get_children():
		if Mgr.REGIONS.has(String(c.name)):
			regions[String(c.name)] = c
	ok(regions.size() == 5, "5 region Node2Ds in scene (got %d)" % regions.size())
	var collisions := 0
	for c in scene.get_children():
		for gc in c.get_children():
			if gc is CollisionPolygon2D:
				collisions += 1
	ok(collisions == 0, "no CollisionPolygon2D baked (got %d)" % collisions)
	for gid in Mgr.REGIONS:
		ok(regions.has(gid), "scene has region " + gid)
		var stage: String = Mgr.REGIONS[gid]["stage"]
		ok(ResourceLoader.exists(stage), gid + " stage resource exists: " + stage)
		# a Visual holder with at least one fill Polygon2D drives geometric hit-testing
		var region: Node2D = regions.get(gid)
		if region:
			var visual := region.get_node_or_null("Visual")
			var has_fill := false
			if visual:
				for v in visual.get_children():
					if v is Polygon2D:
						has_fill = true
						break
			ok(has_fill, gid + " has Visual with >=1 Polygon2D")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
