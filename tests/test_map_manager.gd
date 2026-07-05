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
	# synthesize baked children using the generator's static-ish build against `root`
	var gen: Node2D = Gen.new()
	root.add_child(gen)
	gen.build_into(root)   # bakes region Area2Ds as children of `root`
	gen.free()
	root._connect_regions()

	var area: Area2D = root.get_node("Visayas")
	var visual: Node2D = area.get_node("Visual")

	# hover in recolors to neon synchronously (only position.y is tweened)
	root._on_hover_in(area)
	var neon: Color = Mgr.REGIONS["Visayas"]["neon"]
	var poly: Polygon2D = null
	for v in visual.get_children():
		if v is Polygon2D:
			poly = v
			break
	ok(poly != null and poly.color == neon, "hover recolors fill to neon")

	root._on_hover_out(area)
	ok(poly.color == Mgr.BASE_COLOR, "hover-out reverts to base color")

	# click emits region_selected with correct (name, stage)
	root.region_selected.connect(_on_selected)
	root._select(area)
	ok(emitted.size() >= 1, "region_selected emitted")
	if emitted.size() >= 1:
		ok(emitted[0][0] == "Visayas", "emitted name == Visayas")
		ok(emitted[0][1] == Mgr.REGIONS["Visayas"]["stage"], "emitted stage path correct")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
