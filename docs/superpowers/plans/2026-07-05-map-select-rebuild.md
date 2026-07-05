# Map Select Rebuild (Borderlands) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the LOTA Map Select screen as an interactive Borderlands-styled map of the Philippines where the player clicks one of 5 macro-regions to pick a stage.

**Architecture:** An `@tool` baker (`map_generator.gd`) reads the raw GeoJSON at *edit time*, projects lon/lat into a 1920×1080 design space, groups the 17 admin regions into 5 macro-regions, and bakes persistent `Area2D → CollisionPolygon2D` (hit) + `Visual/Polygon2D` (slate fill) + `Visual/Line2D` (thick black ink stroke) node trees into the scene. A runtime script (`map_manager.gd`) replaces the tool script on the same `MapRoot` node, wires the 5 Area2Ds' signals, animates an aggressive spring hover lift + neon recolor, and on click emits `region_selected` and drives the existing `MatchSelection.stage_data → loading_screen` flow.

**Tech Stack:** Godot 4.7, GDScript. GeoJSON source `.local/philippines_optimized.json` (gitignored, edit-time only). No new dependencies.

## Global Constraints

- **Godot 4.7.** CLI binary: `/home/jacob/Godot_v4.7-stable_linux.x86_64`.
- **Headless test invocation:** `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/<file>.gd` — prints `N checks, M failures`; **exit 0 = pass**.
- **`class_name` is NOT registered in `--script` mode.** Reference shared scripts via `const X := preload("res://...")`, never a bare `class_name`. This applies to tests AND to `map_generator.gd` referencing `map_manager.gd`.
- **Regenerate the class cache** before any full-scene boot: `--headless --import`.
- **Design space:** project coordinates into **1920×1080** (padding 80 px), uniform scale, Y flipped (screen-down).
- **Base fill:** `#343d46`. **Hover lift:** `position.y -= 15`, `TRANS_SPRING`, `EASE_OUT`.
- **Feature folder:** `res://scenes/ui/map_select/` holds `map_generator.gd`, `map_manager.gd`, `outline.gdshader`, `MapSelection.tscn`.
- **Commits:** the user commits their own work — do NOT add a Claude co-author trailer. (Each task ends with a `git add` + `git commit`; keep messages conventional.)
- **Shared truth lives once:** `GROUPS`, `REGIONS`, `BASE_COLOR` are defined in `map_manager.gd`; `map_generator.gd` preloads `map_manager.gd` and reads them. No duplicated dictionaries.

---

### Task 1: Geometry + grouping helpers (`map_generator.gd` statics) and shared region data (`map_manager.gd` consts)

Pure, node-free logic: projection math, GeoJSON exterior-ring extraction (handles both `Polygon` and `MultiPolygon`), ring area, and the region metadata / grouping tables. Fully headless-testable.

**Files:**
- Create: `scenes/ui/map_select/map_manager.gd` (consts only this task)
- Create: `scenes/ui/map_select/map_generator.gd` (static helpers only this task)
- Test: `tests/test_map_generator.gd`

**Interfaces:**
- Produces (`map_manager.gd`):
  - `const BASE_COLOR := Color("#343d46")`
  - `const GROUPS: Dictionary` — 17 `adm1_pcode` string → macro-region id string.
  - `const REGIONS: Dictionary` — 5 macro-region id → `{display:String, stage:String, neon:Color}`.
- Produces (`map_generator.gd`, all `static`):
  - `exterior_rings(geom: Dictionary) -> Array` — array of raw coord rings (`Array` of `[lon,lat]` pairs), exterior ring of every polygon; handles `Polygon` and `MultiPolygon`.
  - `compute_bounds(features: Array, view: Vector2, pad: float) -> Dictionary` — `{lon_min, lat_max, scale, offset: Vector2}`.
  - `project(lon: float, lat: float, b: Dictionary) -> Vector2`.
  - `ring_to_points(ring: Array, b: Dictionary) -> PackedVector2Array`.
  - `ring_area(pts: PackedVector2Array) -> float` — absolute polygon area.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_generator.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_generator.gd`
Expected: FAIL — scripts don't exist / parse error (Gen/Data preload fails).

- [ ] **Step 3: Write `map_manager.gd` consts**

Create `scenes/ui/map_select/map_manager.gd` (runtime body added in Task 4; only shared consts now):

```gdscript
extends Node2D
## Runtime controller for the Map Select screen (MapRoot). Also the single source
## of truth for region grouping + metadata, read by the @tool map_generator.gd.

const BASE_COLOR := Color("#343d46")

## adm1_pcode -> macro-region id. Verified against .local/philippines_optimized.json.
const GROUPS := {
	"PH01": "NorthernLuzon", "PH02": "NorthernLuzon", "PH14": "NorthernLuzon",
	"PH03": "CentralLuzon", "PH13": "CentralLuzon",
	"PH04": "SouthernLuzon", "PH17": "SouthernLuzon", "PH05": "SouthernLuzon",
	"PH06": "Visayas", "PH07": "Visayas", "PH08": "Visayas",
	"PH09": "Mindanao", "PH10": "Mindanao", "PH11": "Mindanao",
	"PH12": "Mindanao", "PH16": "Mindanao", "PH19": "Mindanao",
}

## macro-region id -> display name, stage StageData resource, hover neon color.
const REGIONS := {
	"NorthernLuzon": {"display": "Northern Luzon",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres",
		"neon": Color("#ffd700")},
	"CentralLuzon": {"display": "Central Luzon",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres",
		"neon": Color("#8a2be2")},
	"SouthernLuzon": {"display": "Southern Luzon",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres",
		"neon": Color("#ff2d55")},
	"Visayas": {"display": "Visayas",
		"stage": "res://stages/beach_court/beach_court_data.tres",
		"neon": Color("#00e5ff")},
	"Mindanao": {"display": "Mindanao",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres",
		"neon": Color("#39ff14")},
}
```

- [ ] **Step 4: Write `map_generator.gd` static helpers**

Create `scenes/ui/map_select/map_generator.gd` (bake logic added in Task 2; static helpers now):

```gdscript
@tool
extends Node2D
## Edit-time baker for the Map Select screen. Reads the raw GeoJSON, projects
## lon/lat into a 1920x1080 design space, groups 17 admin regions into 5 macro-
## regions, and bakes persistent Area2D/Polygon2D/Line2D/CollisionPolygon2D nodes.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")

## Exterior ring (index 0) of every polygon; handles Polygon and MultiPolygon.
static func exterior_rings(geom: Dictionary) -> Array:
	var polys: Array = []
	if geom["type"] == "Polygon":
		polys = [geom["coordinates"]]
	else: # MultiPolygon
		polys = geom["coordinates"]
	var rings: Array = []
	for poly in polys:
		if poly.size() > 0:
			rings.append(poly[0])
	return rings

## {lon_min, lat_max, scale, offset} for a uniform, centered, Y-flipped fit.
static func compute_bounds(features: Array, view: Vector2, pad: float) -> Dictionary:
	var lon_min := INF
	var lon_max := -INF
	var lat_min := INF
	var lat_max := -INF
	for f in features:
		for ring in exterior_rings(f["geometry"]):
			for pt in ring:
				lon_min = min(lon_min, pt[0])
				lon_max = max(lon_max, pt[0])
				lat_min = min(lat_min, pt[1])
				lat_max = max(lat_max, pt[1])
	var lon_span: float = max(lon_max - lon_min, 0.000001)
	var lat_span: float = max(lat_max - lat_min, 0.000001)
	var scale: float = min((view.x - 2.0 * pad) / lon_span, (view.y - 2.0 * pad) / lat_span)
	# center the fitted map within the padded viewport
	var offset := Vector2(
		((view.x - 2.0 * pad) - lon_span * scale) * 0.5,
		((view.y - 2.0 * pad) - lat_span * scale) * 0.5)
	return {"lon_min": lon_min, "lat_max": lat_max, "scale": scale, "offset": offset,
		"pad": pad}

static func project(lon: float, lat: float, b: Dictionary) -> Vector2:
	return Vector2(
		b["pad"] + b["offset"].x + (lon - b["lon_min"]) * b["scale"],
		b["pad"] + b["offset"].y + (b["lat_max"] - lat) * b["scale"])

static func ring_to_points(ring: Array, b: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for pt in ring:
		pts.append(project(pt[0], pt[1], b))
	return pts

static func ring_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		a += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return abs(a) * 0.5
```

- [ ] **Step 5: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_generator.gd`
Expected: `... checks, 0 failures`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/map_select/map_generator.gd scenes/ui/map_select/map_manager.gd tests/test_map_generator.gd
git commit -m "feat(map): projection + grouping helpers and shared region data [7.6]"
```

---

### Task 2: `@tool` node baker (`build_map` / `clear_map`)

Add the edit-time bake to `map_generator.gd`: read the GeoJSON, and for each macro-region build one `Area2D` containing a `Visual` `Node2D` (per-ring `Polygon2D` slate fill + closed black `Line2D` stroke) plus per-ring `CollisionPolygon2D`. Testable headless by instantiating the script as a node and calling `build()` directly (no editor needed).

**Files:**
- Modify: `scenes/ui/map_select/map_generator.gd` (add exports + `build()` / `clear()`)
- Test: `tests/test_map_baker.gd`

**Interfaces:**
- Consumes: all Task 1 statics; `Data.GROUPS`, `Data.REGIONS`, `Data.BASE_COLOR`.
- Produces (instance methods on the `MapRoot` node):
  - `build() -> void` — clears then bakes the 5 region subtrees as children of `self`.
  - `clear() -> void` — frees previously baked region children (idempotent).
  - `@export var build_map: bool` setter → `build()`; `@export var clear_map: bool` setter → `clear()`.
  - Node contract per region: `Area2D` (name = macro-region id) → child `Node2D` named `"Visual"` (holds `Polygon2D` + `Line2D` per ring) and sibling `CollisionPolygon2D` per ring.
- Constants: `const SOURCE := "res://.local/philippines_optimized.json"`, `const VIEW := Vector2(1920, 1080)`, `const PAD := 80.0`, `const MIN_AREA := 8.0`, `const OUTLINE_WIDTH := 6.0`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_baker.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_baker.gd`
Expected: FAIL — `build()`/`clear()`/`SOURCE` not defined (parse error or missing method).

- [ ] **Step 3: Add exports, constants, and bake logic to `map_generator.gd`**

Append to `scenes/ui/map_select/map_generator.gd` (below the statics):

```gdscript
const SOURCE := "res://.local/philippines_optimized.json"
const VIEW := Vector2(1920, 1080)
const PAD := 80.0
const MIN_AREA := 8.0        # drop islets smaller than this (projected px^2)
const OUTLINE_WIDTH := 6.0
const OUTLINE_SHADER := "res://scenes/ui/map_select/outline.gdshader"

@export var build_map: bool = false:
	set(v):
		build_map = false
		if v:
			build()

@export var clear_map: bool = false:
	set(v):
		clear_map = false
		if v:
			clear()

func clear() -> void:
	for c in get_children():
		if c is Area2D:
			c.free()  # immediate: editor re-bake must not double up

func build() -> void:
	clear()
	var txt := FileAccess.get_file_as_string(SOURCE)
	if txt.is_empty():
		push_error("Map source not found or empty: " + SOURCE)
		return
	var doc: Dictionary = JSON.parse_string(txt)
	var features: Array = doc["features"]
	var b := compute_bounds(features, VIEW, PAD)

	# collect projected exterior rings per macro-region
	var rings_by_region := {}
	for gid in Data.REGIONS:
		rings_by_region[gid] = []
	for f in features:
		var pcode: String = f["properties"]["adm1_pcode"]
		if not Data.GROUPS.has(pcode):
			continue
		var gid: String = Data.GROUPS[pcode]
		for ring in exterior_rings(f["geometry"]):
			var pts := ring_to_points(ring, b)
			if ring_area(pts) >= MIN_AREA:
				rings_by_region[gid].append(pts)

	var owner_root := get_tree().edited_scene_root
	for gid in Data.REGIONS:
		_bake_region(gid, rings_by_region[gid], owner_root)

func _bake_region(gid: String, rings: Array, owner_root: Node) -> void:
	var area := Area2D.new()
	area.name = gid
	add_child(area)
	if owner_root:
		area.set_owner(owner_root)

	var visual := Node2D.new()
	visual.name = "Visual"
	area.add_child(visual)
	if owner_root:
		visual.set_owner(owner_root)

	var shader: Shader = load(OUTLINE_SHADER) if ResourceLoader.exists(OUTLINE_SHADER) else null

	for pts in rings:
		# fill
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = Data.BASE_COLOR
		if shader:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			poly.material = mat
		visual.add_child(poly)
		if owner_root:
			poly.set_owner(owner_root)
		# ink stroke
		var line := Line2D.new()
		var closed := PackedVector2Array(pts)
		if closed.size() > 0:
			closed.append(closed[0])
		line.points = closed
		line.width = OUTLINE_WIDTH
		line.default_color = Color.BLACK
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		visual.add_child(line)
		if owner_root:
			line.set_owner(owner_root)
		# collision (sibling of Visual, under Area2D)
		var col := CollisionPolygon2D.new()
		col.polygon = pts
		area.add_child(col)
		if owner_root:
			col.set_owner(owner_root)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_baker.gd`
Expected: `... checks, 0 failures`, exit 0. (If it prints `SKIP`, the GeoJSON is missing — restore `.local/philippines_optimized.json` before proceeding.)

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_generator.gd tests/test_map_baker.gd
git commit -m "feat(map): @tool baker for 5 macro-region Area2D/Polygon2D/Line2D trees [7.6]"
```

---

### Task 3: `outline.gdshader`

Deliver the spec-required CanvasItem outline shader (reusable textured-fill stroke). Parse-checked headless.

**Files:**
- Create: `scenes/ui/map_select/outline.gdshader`
- Test: `tests/test_outline_shader.gd`

**Interfaces:**
- Produces: a CanvasItem shader exposing `uniform float outline_width` and `uniform vec4 outline_color: source_color`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_outline_shader.gd`:

```gdscript
extends SceneTree

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var path := "res://scenes/ui/map_select/outline.gdshader"
	ok(ResourceLoader.exists(path), "shader exists")
	var sh: Shader = load(path)
	ok(sh != null, "shader loads")
	if sh:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		# uniforms present and compile OK (defaults readable via material)
		mat.set_shader_parameter("outline_width", 6.0)
		mat.set_shader_parameter("outline_color", Color.BLACK)
		ok(mat.get_shader_parameter("outline_width") == 6.0, "outline_width uniform set")
		ok(mat.get_shader_parameter("outline_color") == Color.BLACK, "outline_color uniform set")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_outline_shader.gd`
Expected: FAIL — `shader exists` false.

- [ ] **Step 3: Write the shader**

Create `scenes/ui/map_select/outline.gdshader`:

```glsl
shader_type canvas_item;
// Graphic-novel outer stroke for textured CanvasItem fills. Samples TEXTURE alpha
// in a ring at outline_width; where this pixel is transparent but a neighbor is
// opaque, output a hard, un-blurred outline_color. Requires a texture with alpha.

uniform float outline_width = 6.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a > 0.5) {
		COLOR = tex;
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float hit = 0.0;
		// 8-direction ring sample
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x, 0.0)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x, 0.0)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(0.0,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
		hit = max(hit, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);
		// hard step: no blur, no gradient
		COLOR = (hit > 0.5) ? outline_color : vec4(0.0);
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_outline_shader.gd`
Expected: `... checks, 0 failures`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/outline.gdshader tests/test_outline_shader.gd
git commit -m "feat(map): graphic-novel outline.gdshader (hard black stroke) [7.6]"
```

---

### Task 4: Runtime controller (`map_manager.gd`) — hover, click, selection

Add the runtime body to `map_manager.gd`: find the 5 baked Area2Ds, connect signals in code, animate the aggressive spring hover lift + neon recolor + fatter ink stroke, and on click emit `region_selected` then drive `MatchSelection.stage_data → loading_screen`.

**Files:**
- Modify: `scenes/ui/map_select/map_manager.gd` (add runtime body under the consts)
- Test: `tests/test_map_manager.gd`

**Interfaces:**
- Consumes: `GROUPS`, `REGIONS`, `BASE_COLOR`; baked node contract from Task 2; `map_generator.gd.build()` (test harness only, to synthesize children).
- Produces:
  - `signal region_selected(region_name: String, stage_name: String)`
  - `func _on_hover_in(area: Area2D) -> void`
  - `func _on_hover_out(area: Area2D) -> void`
  - `func _on_region_input(_viewport, event: InputEvent, _shape_idx: int, area: Area2D) -> void`
  - `func _select(area: Area2D) -> void` — emits signal, sets `MatchSelection.stage_data`, changes scene.
  - `@export var label_path: NodePath` — optional CanvasLayer label updated on hover.
  - const `HOVER_LIFT := -15.0`, `HOVER_OUTLINE := 12.0`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_manager.gd`:

```gdscript
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
```

> Note: this test calls `gen.build_into(root)` and `root._connect_regions()`. Add `build_into(target)` to the generator (Step 3a) and the runtime methods to the manager (Step 3b). `_select` must guard `change_scene_to_file` so the headless test doesn't actually switch scenes (see Step 3b).

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_manager.gd`
Expected: FAIL — `build_into` / `_connect_regions` / `_on_hover_in` not defined.

- [ ] **Step 3a: Refactor generator to bake into an arbitrary target**

In `scenes/ui/map_select/map_generator.gd`, extract the target from `build()` so a test (and the manager) can bake into any node. Replace the `build()` body's region loop tail and add `build_into`:

```gdscript
func build() -> void:
	build_into(self)

func build_into(target: Node2D) -> void:
	for c in target.get_children():
		if c is Area2D:
			c.free()
	var txt := FileAccess.get_file_as_string(SOURCE)
	if txt.is_empty():
		push_error("Map source not found or empty: " + SOURCE)
		return
	var doc: Dictionary = JSON.parse_string(txt)
	var features: Array = doc["features"]
	var b := compute_bounds(features, VIEW, PAD)
	var rings_by_region := {}
	for gid in Data.REGIONS:
		rings_by_region[gid] = []
	for f in features:
		var pcode: String = f["properties"]["adm1_pcode"]
		if not Data.GROUPS.has(pcode):
			continue
		var gid: String = Data.GROUPS[pcode]
		for ring in exterior_rings(f["geometry"]):
			var pts := ring_to_points(ring, b)
			if ring_area(pts) >= MIN_AREA:
				rings_by_region[gid].append(pts)
	var owner_root := get_tree().edited_scene_root
	for gid in Data.REGIONS:
		_bake_region_into(target, gid, rings_by_region[gid], owner_root)
```

Rename `_bake_region(gid, rings, owner_root)` to `_bake_region_into(target: Node2D, gid, rings, owner_root)` and change its first line `add_child(area)` → `target.add_child(area)` (all other `set_owner` lines unchanged). Delete the now-unused old `build()` body/`clear()` uses `get_children()` still (fine — regions are direct children in editor use).

Re-run `tests/test_map_baker.gd` to confirm the refactor didn't break it:
Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_baker.gd`
Expected: `... checks, 0 failures`.

- [ ] **Step 3b: Add runtime body to `map_manager.gd`**

Append to `scenes/ui/map_select/map_manager.gd`:

```gdscript
signal region_selected(region_name: String, stage_name: String)

const HOVER_LIFT := -15.0
const HOVER_OUTLINE := 12.0

@export var label_path: NodePath

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_connect_regions()

func _connect_regions() -> void:
	for gid in REGIONS:
		var area := get_node_or_null(NodePath(gid)) as Area2D
		if area == null:
			continue
		area.input_pickable = true
		if not area.mouse_entered.is_connected(_on_hover_in):
			area.mouse_entered.connect(_on_hover_in.bind(area))
			area.mouse_exited.connect(_on_hover_out.bind(area))
			area.input_event.connect(_on_region_input.bind(area))

func _visual_of(area: Area2D) -> Node2D:
	return area.get_node_or_null("Visual") as Node2D

func _on_hover_in(area: Area2D) -> void:
	var gid := String(area.name)
	var visual := _visual_of(area)
	if visual == null:
		return
	area.z_index = 1
	var neon: Color = REGIONS[gid]["neon"]
	for child in visual.get_children():
		if child is Polygon2D:
			child.color = neon
		elif child is Line2D:
			child.width = HOVER_OUTLINE
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", HOVER_LIFT, 0.35)
	_set_label(REGIONS[gid]["display"])

func _on_hover_out(area: Area2D) -> void:
	var visual := _visual_of(area)
	if visual == null:
		return
	area.z_index = 0
	for child in visual.get_children():
		if child is Polygon2D:
			child.color = BASE_COLOR
		elif child is Line2D:
			child.width = 6.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position:y", 0.0, 0.35)
	_set_label("")

func _on_region_input(_viewport: Node, event: InputEvent, _shape_idx: int, area: Area2D) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(area)

func _select(area: Area2D) -> void:
	var gid := String(area.name)
	var display: String = REGIONS[gid]["display"]
	var stage_path: String = REGIONS[gid]["stage"]
	region_selected.emit(display, stage_path)
	# Autoload access under --script mode: bare identifier is unavailable.
	var ms := Engine.get_main_loop().root.get_node_or_null("MatchSelection")
	if ms and ResourceLoader.exists(stage_path):
		ms.stage_data = load(stage_path)
	# Guard scene switch so headless --script tests don't navigate away.
	if not Engine.is_editor_hint() and get_tree().current_scene != null:
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

func _set_label(text: String) -> void:
	if label_path.is_empty():
		return
	var lbl := get_node_or_null(label_path)
	if lbl and lbl is Label:
		lbl.text = text
```

> The test's `_select(area)` runs with `get_tree().current_scene == null` (nodes added via `get_root().add_child`), so the scene switch is skipped while the signal + `stage_data` still fire.

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_manager.gd`
Expected: `... checks, 0 failures`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_manager.gd scenes/ui/map_select/map_generator.gd tests/test_map_manager.gd
git commit -m "feat(map): runtime hover/click controller + region_selected signal [7.6]"
```

---

### Task 5: Scene assembly, flow wiring, and retirement of the old implementation

Build `MapSelection.tscn` (bake regions via the `@tool`, then swap the script to `map_manager.gd`), add the CanvasLayer UI, repoint `character_select.gd`, delete the retired files, and add a full-scene integration test.

**Files:**
- Create: `scenes/ui/map_select/MapSelection.tscn`
- Modify: `scripts/character_select.gd:250`
- Delete: `scripts/map_select.gd` (+`.uid`), `scripts/ui/map_region.gd` (+`.uid`), `scenes/map_select.tscn`, `data/map_regions.json`, `scripts/dev/bake_map_regions.py`, `scripts/dev/__pycache__/`, `tests/test_map_select.gd` (+`.uid`)
- Test: `tests/test_map_select_scene.gd`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `res://scenes/ui/map_select/MapSelection.tscn` with root `MapRoot` (script `map_manager.gd`), 5 baked region Area2Ds, a `CanvasLayer/UI` with a title `Label` and a hover `Label`, and `MapRoot.label_path` pointing at the hover label.

- [ ] **Step 1: Author `MapSelection.tscn` in the editor and bake**

Manual editor steps (the baker needs `edited_scene_root`):
1. New scene, root `Node2D` named `MapRoot`. Attach `scenes/ui/map_select/map_generator.gd` (the `@tool` script) temporarily.
2. In the Inspector, tick **Build Map**. Confirm 5 `Area2D` children (NorthernLuzon, CentralLuzon, SouthernLuzon, Visayas, Mindanao) appear, each with a `Visual` node and `CollisionPolygon2D`s.
3. Add `CanvasLayer` → `UI`; under it a title `Label` ("SELECT YOUR BATTLEGROUND", bold/uppercase, using `art/fonts/BebasNeue-Regular.ttf`) and a second `Label` named `RegionName` (bottom-center, `art/fonts/Bangers-Regular.ttf`).
4. **Swap the root script** from `map_generator.gd` to `scenes/ui/map_select/map_manager.gd` (right-click root → change script). The baked children persist.
5. Set `MapRoot.Label Path` to `CanvasLayer/UI/RegionName`.
6. Save as `scenes/ui/map_select/MapSelection.tscn`.

- [ ] **Step 2: Write the failing integration test**

Create `tests/test_map_select_scene.gd`:

```gdscript
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
```

- [ ] **Step 3: Run test to verify it fails (or passes if scene already correct)**

First regenerate the class cache, then run:
```
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --import
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_select_scene.gd
```
Expected initially: FAIL if the scene isn't saved/wired yet. Fix wiring in the editor until it passes: `... checks, 0 failures`.

- [ ] **Step 4: Repoint the game flow**

In `scripts/character_select.gd`, change the handoff target:

```gdscript
	get_tree().change_scene_to_file("res://scenes/ui/map_select/MapSelection.tscn")
```

(Replaces the `res://scenes/map_select.tscn` line at ~`:250`.)

- [ ] **Step 5: Delete the retired implementation**

```bash
git rm scripts/map_select.gd scripts/map_select.gd.uid \
       scripts/ui/map_region.gd scripts/ui/map_region.gd.uid \
       scenes/map_select.tscn \
       data/map_regions.json \
       scripts/dev/bake_map_regions.py \
       tests/test_map_select.gd tests/test_map_select.gd.uid
rm -rf scripts/dev/__pycache__
```

- [ ] **Step 6: Verify no stale references remain**

Run: `grep -rn "scenes/map_select.tscn\|scripts/map_select\|map_region\|data/map_regions" --include=*.gd --include=*.tscn --include=*.godot .`
Expected: no matches (empty output).

- [ ] **Step 7: Regenerate class cache and run the full suite**

```
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --import
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_generator.gd
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_baker.gd
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_outline_shader.gd
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_manager.gd
/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --script res://tests/test_map_select_scene.gd
```
Expected: every run prints `... 0 failures` and exits 0.

- [ ] **Step 8: Commit**

```bash
git add scenes/ui/map_select/MapSelection.tscn scripts/character_select.gd tests/test_map_select_scene.gd
git add -u
git commit -m "feat(map): MapSelection scene, flow wiring, retire old stage/map select [7.6]"
```

---

## Self-Review Notes

- **Spec coverage:** §2 files → Tasks 1–5; §3 projection → Task 1; §4 grouping (corrected pcodes, CAR=PH14) → Task 1 consts; §5 MultiPolygon node tree → Task 2; §6 runtime hover/click/signal → Task 4; §7 scene + flow → Task 5; §8 shader → Task 3; §9 testing → tests in every task + Task 5 integration. All covered.
- **Type consistency:** `build_into`/`_bake_region_into`/`_connect_regions`/`_on_hover_in`/`_on_hover_out`/`_on_region_input`/`_select` used consistently across tasks; `REGIONS`/`GROUPS`/`BASE_COLOR` defined once in `map_manager.gd`, preloaded by `map_generator.gd`.
- **Headless caveats honored:** `preload` over `class_name`; `--import` before scene boot; autoload accessed via `root.get_node("MatchSelection")`; scene-switch guarded so tests don't navigate.
- **Known manual step:** Task 5 Step 1 (baking + script swap + UI) is editor work the baker requires (`edited_scene_root`); the integration test gates its correctness.
```
