extends SceneTree
## Headless integration check for map select (7.6): baked data integrity, point-in-
## polygon hit-testing, and the confirm handoff (sets MatchSelection.stage_data,
## emits stage_confirmed).

var _checks := 0
var _failures := 0
var _emitted: Array = []

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	# --- baked data integrity ---
	var f := FileAccess.open("res://data/map_regions.json", FileAccess.READ)
	_check(f != null, "map_regions.json exists")
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var regions: Array = doc["regions"]
	_check(regions.size() == 5, "5 regions baked")
	var nums: Array = []
	var accents := {1: "#f5b431", 2: "#22d3ee", 3: "#ef4444", 4: "#b366ff", 5: "#fb7a2d"}
	for r: Dictionary in regions:
		nums.append(int(r["region_number"]))
		_check(r["outline_polygons"].size() >= 1, "region %d has >=1 ring" % int(r["id"]))
		var ok_rings := true
		for ring: Array in r["outline_polygons"]:
			if ring.size() < 6:
				ok_rings = false
		_check(ok_rings, "region %d rings are non-degenerate" % int(r["id"]))
		_check(str(r["accent_color"]) == accents[int(r["id"])], "region %d accent matches" % int(r["id"]))
		var sd: Resource = load(str(r["stage_data_path"]))
		_check(sd != null and sd.stage_name == str(r["stage_name"]), "region %d stage loads + names match" % int(r["id"]))
	nums.sort()
	_check(nums == [1, 2, 3, 4, 5], "region_numbers are 1..5")

	# --- hit-testing (point-in-polygon) ---
	var scene: PackedScene = load("res://scenes/map_select.tscn")
	var screen: Node = scene.instantiate()
	get_root().add_child(screen)
	# Under a SceneTree --script entrypoint, _ready() isn't fired synchronously by
	# add_child() — it's deferred to the next frame. Wait one frame so map_select's
	# _ready() (which builds the MapRegion children) has actually run.
	await process_frame
	var map_root: Node2D = screen.get_node("MapContainer")
	var region_nodes: Dictionary = {}   # id -> MapRegion
	for child in map_root.get_children():
		region_nodes[child.region_id] = child

	for r: Dictionary in regions:
		var id := int(r["id"])
		var node: Node = region_nodes.get(id)
		_check(node != null, "region %d has a MapRegion node" % id)
		if node == null:
			continue
		var sample: Variant = _find_inside_point(r["outline_polygons"])
		_check(sample != null, "region %d has a findable inside sample point" % id)
		if sample != null:
			_check(node.contains_point(sample) == true,
				"region %d contains_point(sample) is true" % id)
		_check(node.contains_point(Vector2(-9999, -9999)) == false,
			"region %d contains_point(far outside) is false" % id)

	# --- confirm handoff ---
	# `MatchSelection` is an autoload; under --script the bare identifier isn't
	# registered as a compile-time global (only real scene/main-scene runs get that),
	# so reach it dynamically via the root node instead.
	var match_selection: Node = get_root().get_node("MatchSelection")
	_check(match_selection != null, "MatchSelection autoload is reachable")
	match_selection.stage_data = null
	screen.stage_confirmed.connect(func(id: int, stage: String, fighter: String) -> void:
		_emitted = [id, stage, fighter])
	screen.select_region(3)          # Metro Manila
	screen.lock_selection()
	_check(match_selection.stage_data != null, "confirm set MatchSelection.stage_data")
	_check(match_selection.stage_data != null and match_selection.stage_data.stage_name == "Barangay Boxing Ring",
		"stage_data is the selected region's stage")
	_check(_emitted.size() == 3 and _emitted[0] == 3, "stage_confirmed emitted with region id 3")
	_check(_emitted.size() == 3 and _emitted[2] == "Dirty Boxing Fighter", "stage_confirmed carries the fighter")
	screen.queue_free()

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _to_points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < flat.size() - 1:
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
		i += 2
	return out


func _find_inside_point(rings_raw: Array) -> Variant:
	## Grid-scan each ring's bbox for a point Geometry2D confirms is inside. Returns
	## the first hit, or null if no ring yields one (shouldn't happen for real data).
	for ring_raw: Array in rings_raw:
		var ring := _to_points(ring_raw)
		if ring.size() < 3:
			continue
		var min_v := ring[0]
		var max_v := ring[0]
		for p: Vector2 in ring:
			min_v.x = min(min_v.x, p.x)
			min_v.y = min(min_v.y, p.y)
			max_v.x = max(max_v.x, p.x)
			max_v.y = max(max_v.y, p.y)
		var steps := 40
		var dx: float = (max_v.x - min_v.x) / steps
		var dy: float = (max_v.y - min_v.y) / steps
		for iy in range(steps + 1):
			for ix in range(steps + 1):
				var candidate := Vector2(min_v.x + ix * dx, min_v.y + iy * dy)
				if Geometry2D.is_point_in_polygon(candidate, ring):
					return candidate
	return null
