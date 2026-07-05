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

	var areas := {}
	for c in scene.get_children():
		if c is Area2D:
			areas[c.name] = c
	ok(areas.size() == 5, "5 region Area2Ds in scene (got %d)" % areas.size())
	for gid in Mgr.REGIONS:
		ok(areas.has(gid), "scene has region " + gid)
		var stage: String = Mgr.REGIONS[gid]["stage"]
		ok(ResourceLoader.exists(stage), gid + " stage resource exists: " + stage)
		# signals connected
		var area: Area2D = areas.get(gid)
		if area:
			ok(area.mouse_entered.get_connections().size() >= 1, gid + " mouse_entered connected")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
