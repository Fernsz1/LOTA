extends SceneTree
## Headless builder for scenes/ui/map_select/MapSelection.tscn.
## Bakes regions via the @tool generator, swaps in the runtime script, adds the
## CanvasLayer UI, wires label_path, sets owners, and packs/saves the scene.
## Run with: godot --headless --script res://scripts/dev/build_map_scene.gd

const MapManagerScript := preload("res://scenes/ui/map_select/map_manager.gd")
const MapGeneratorScript := preload("res://scenes/ui/map_select/map_generator.gd")

const OUT_PATH := "res://scenes/ui/map_select/MapSelection.tscn"
const TITLE_FONT := "res://art/fonts/BebasNeue-Regular.ttf"
const REGION_FONT := "res://art/fonts/Bangers-Regular.ttf"

func _init() -> void:
	# 1. Scene root.
	var root := Node2D.new()
	root.name = "MapRoot"

	# 2. Add to tree so tweens/tree ops used elsewhere are valid.
	get_root().add_child(root)

	# 3. Bake regions using the @tool generator (temporarily attached logic).
	var gen: Node2D = MapGeneratorScript.new()
	get_root().add_child(gen)
	gen.build_into(root)
	gen.free()

	# Swap the root's script to the runtime controller now that baking is done.
	root.set_script(MapManagerScript)

	# 4. CanvasLayer UI.
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	root.add_child(canvas)

	var title := Label.new()
	title.name = "Title"
	title.text = "SELECT YOUR BATTLEGROUND"
	if ResourceLoader.exists(TITLE_FONT):
		title.add_theme_font_override("font", load(TITLE_FONT))
	title.add_theme_font_size_override("font_size", 72)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-500, 40)
	title.size = Vector2(1000, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	canvas.add_child(title)

	var region_name := Label.new()
	region_name.name = "RegionName"
	region_name.text = ""
	if ResourceLoader.exists(REGION_FONT):
		region_name.add_theme_font_override("font", load(REGION_FONT))
	region_name.add_theme_font_size_override("font_size", 56)
	region_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	region_name.position = Vector2(-500, -140)
	region_name.size = Vector2(1000, 100)
	region_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	canvas.add_child(region_name)

	# 5. Wire hover label.
	root.label_path = NodePath("UI/RegionName")

	# 6. Set owners for everything under root so packing persists it.
	_set_owners_recursive(root, root)

	# 7. Pack and save.
	var ps := PackedScene.new()
	var pack_result := ps.pack(root)
	if pack_result != OK:
		print("FAILURE: pack() returned ", pack_result)
		quit(1)
		return

	var save_result := ResourceSaver.save(ps, OUT_PATH)
	if save_result != OK:
		print("FAILURE: ResourceSaver.save() returned ", save_result)
		quit(1)
		return

	print("SUCCESS: saved ", OUT_PATH)
	quit(0)

func _set_owners_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child != root:
			child.set_owner(root)
		_set_owners_recursive(child, root)
