extends SceneTree

const Gen := preload("res://scenes/ui/map_select/map_generator.gd")
const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: ", msg)

func _init() -> void:
	# --- Grouping table: all 17 pcodes present, exactly 5 groups ---
	ok(Data.GROUPS.size() == 17, "17 pcodes mapped")
	var groups := {}
	for k in Data.GROUPS:
		groups[Data.GROUPS[k]] = true
	ok(groups.size() == 5, "exactly 5 macro-regions")
	ok(Data.GROUPS["PH14"] == "NorthernLuzon", "CAR (PH14) -> NorthernLuzon")
	ok(Data.GROUPS["PH13"] == "CentralLuzon", "NCR (PH13) -> CentralLuzon")
	ok(Data.GROUPS["PH19"] == "Mindanao", "BARMM (PH19) -> Mindanao")
	ok(Data.GROUPS["PH16"] == "Mindanao", "Caraga (PH16) -> Mindanao")
	# --- Every group id has REGIONS metadata resolving to an existing stage ---
	for gid in groups:
		ok(Data.REGIONS.has(gid), "REGIONS has " + gid)
		var stage: String = Data.REGIONS[gid]["stage"]
		ok(FileAccess.file_exists(stage), "stage exists: " + stage)

	# --- exterior_rings handles Polygon and MultiPolygon ---
	var poly := {"type": "Polygon", "coordinates": [
		[[0,0],[2,0],[2,2],[0,2],[0,0]],   # exterior
		[[0.5,0.5],[1,0.5],[1,1],[0.5,0.5]] # hole (ignored)
	]}
	ok(Gen.exterior_rings(poly).size() == 1, "Polygon -> 1 exterior ring")
	var multi := {"type": "MultiPolygon", "coordinates": [
		[[[0,0],[1,0],[1,1],[0,0]]],
		[[[5,5],[6,5],[6,6],[5,5]]]
	]}
	ok(Gen.exterior_rings(multi).size() == 2, "MultiPolygon -> 2 exterior rings")

	# --- projection: lon_min/lat_max corner maps to pad offset, in-bounds ---
	var feats := [{"geometry": {"type": "Polygon",
		"coordinates": [[[100,0],[110,0],[110,20],[100,20],[100,0]]]}}]
	var b := Gen.compute_bounds(feats, Vector2(1920, 1080), 80.0)
	var p := Gen.project(100, 20, b) # lon_min, lat_max -> top-left inside padding
	ok(abs(p.x - (80.0 + b["offset"].x)) < 0.01 and abs(p.y - (80.0 + b["offset"].y)) < 0.01,
		"top-left corner projects to padding+offset")
	var p2 := Gen.project(110, 0, b)  # far corner
	ok(p2.x <= 1920 - 80 + 0.01 and p2.y <= 1080 - 80 + 0.01, "far corner within padded view")

	# --- ring_area ---
	var square := PackedVector2Array([Vector2(0,0), Vector2(2,0), Vector2(2,2), Vector2(0,2)])
	ok(abs(Gen.ring_area(square) - 4.0) < 0.001, "unit-square area == 4")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
