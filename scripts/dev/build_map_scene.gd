extends SceneTree
## Headless builder for scenes/ui/map_select/MapSelection.tscn. Bakes the tilted,
## extruded map + background + markers + hi-fi UI, wires the manager, packs, saves.
## Run: godot --headless --path . --script res://scripts/dev/build_map_scene.gd

const MapManagerScript := preload("res://scenes/ui/map_select/map_manager.gd")
const MapGeneratorScript := preload("res://scenes/ui/map_select/map_generator.gd")
const MapUiScript := preload("res://scenes/ui/map_select/map_ui.gd")
const MapMarkersScript := preload("res://scenes/ui/map_select/map_markers.gd")

const OUT_PATH := "res://scenes/ui/map_select/MapSelection.tscn"
const BG_SHADER := "res://scenes/ui/map_select/background.gdshader"

func _init() -> void:
	var root := Node2D.new()
	root.name = "MapRoot"
	get_root().add_child(root)

	# 1. Background — full-viewport ColorRect with the dusk-ocean shader.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.size = Vector2(1280, 720)
	bg.z_index = -10
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never intercept map clicks/hover
	if ResourceLoader.exists(BG_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(BG_SHADER)
		bg.material = mat
	root.add_child(bg)

	# 2. MapPlane — bake regions into it, then apply the static affine tilt.
	var plane := Node2D.new()
	plane.name = "MapPlane"
	plane.z_index = 1
	root.add_child(plane)
	var gen: Node2D = MapGeneratorScript.new()
	get_root().add_child(gen)
	gen.build_into(plane)
	gen.free()
	var centre := _archipelago_centre(plane)
	plane.transform = MapManagerScript.tilt_transform(
		centre, MapManagerScript.TILT_ROT_DEG, MapManagerScript.TILT_SCALE_Y)
	# Scale + centre the tilted map into a framed region: below the header, left of
	# the info panel (x >= 884), with margins so nothing touches the screen edge.
	_fit_plane(plane, Rect2(64, 214, 772, 452))

	# 3. Markers layer (auto-builds at runtime from centroids + plane transform).
	var markers: Node2D = MapMarkersScript.new()
	markers.name = "Markers"
	root.add_child(markers)
	markers.map_plane_path = NodePath("../MapPlane")

	# 4. Overlay UI.
	var ui: CanvasLayer = MapUiScript.new()
	ui.name = "UI"
	root.add_child(ui)

	# 5. Runtime controller + wiring.
	root.set_script(MapManagerScript)
	root.map_plane_path = NodePath("MapPlane")
	root.markers_path = NodePath("Markers")
	root.ui_path = NodePath("UI")

	# 6. Own everything under root so packing persists it.
	_set_owners_recursive(root, root)

	# 7. Pack + save.
	var ps := PackedScene.new()
	if ps.pack(root) != OK:
		print("FAILURE: pack() failed")
		quit(1)
		return
	if ResourceSaver.save(ps, OUT_PATH) != OK:
		print("FAILURE: save() failed")
		quit(1)
		return
	print("SUCCESS: saved ", OUT_PATH)
	quit(0)

## Prepend a uniform scale+translate to plane.transform so the tilted map's world
## bounding box fits centred inside `target`. Markers (which read plane.transform *
## centroid at runtime) follow automatically.
func _fit_plane(plane: Node2D, target: Rect2) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for region in plane.get_children():
		var top := region.get_node_or_null("Visual/Top") as Node2D
		if top == null:
			continue
		for poly in top.get_children():
			if poly is Polygon2D:
				for p in poly.polygon:
					var w: Vector2 = plane.transform * p
					lo = lo.min(w); hi = hi.max(w)
	if lo.x > hi.x:
		return
	var box_size := hi - lo
	var s: float = minf(target.size.x / box_size.x, target.size.y / box_size.y)
	var box_c := (lo + hi) * 0.5
	var target_c := target.position + target.size * 0.5
	var fit := Transform2D(0.0, target_c) \
		* Transform2D(Vector2(s, 0.0), Vector2(0.0, s), Vector2.ZERO) \
		* Transform2D(0.0, -box_c)
	plane.transform = fit * plane.transform

## Bounding-box centre of all baked region centroids (in plane-local space).
func _archipelago_centre(plane: Node2D) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for gid in MapManagerScript.REGIONS:
		var r := plane.get_node_or_null(NodePath(gid)) as Node2D
		if r and r.has_meta("centroid"):
			var c: Vector2 = r.get_meta("centroid")
			lo = lo.min(c); hi = hi.max(c)
	return (lo + hi) * 0.5

func _set_owners_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child != root:
			child.set_owner(root)
		_set_owners_recursive(child, root)
