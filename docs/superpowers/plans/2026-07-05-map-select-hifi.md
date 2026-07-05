# Map Select — Hi-Fi Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Map Select screen to the hi-fi handoff — a cel-shaded, affine-tilted Philippine archipelago with extruded landmasses, pulsing beacons, and a skewed/notched overlay UI (info panel, stage preview, confirm button, locked-in ribbon).

**Architecture:** Keep the existing pure-2D pipeline (`@tool` generator bakes region `Node2D`s; runtime `map_manager.gd` does geometric point-in-polygon hit-testing). Layer the art on top: a `MapPlane` `Node2D` carries a static affine tilt (rotate −20°, squash Y by cos 49°) and parents the 5 region nodes; the generator draws each ring as a 3-pass extrusion (cast shadow → underside → top face); a dusk-ocean shader paints the background; a hand-drawn (`_draw`) overlay renders the skewed UI; a markers layer draws upright beacons at each region's projected centroid. No 3D subsystem — the tilt is a single Transform2D, zero per-frame cost.

**Tech Stack:** Godot 4.7, GDScript, canvas_item shaders. Pure 2D (`canvas_items` stretch, 1280×720 base viewport). Headless SceneTree test scripts.

## Global Constraints

- **Engine:** Godot 4.7. Binary: `/home/jacob/Godot_v4.7-stable_linux.x86_64`.
- **Run any test / build script:** `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://<path>.gd` — exit 0 = pass; scripts print `N checks, M failures`.
- **`--script` mode has NO global `class_name` symbols.** Reference shared scripts via `const X := preload("res://…")`, never a bare class name. Autoloads (e.g. `MatchSelection`) are reached through `get_tree().root.get_node_or_null("MatchSelection")`, never the bare identifier.
- **Base viewport:** 1280×720 (`canvas_items`). All map geometry is projected into this space by `map_generator.gd`. All UI coordinates in this plan are in 1280×720 screen space.
- **Hit-testing is geometric only.** No `Area2D` / `CollisionPolygon2D` anywhere in the map (convex decomposition fails on self-touching coastline rings). Use `Geometry2D.is_point_in_polygon`.
- **Commits:** commit per task as each task's final step. Do NOT add a `Co-Authored-By: Claude` trailer (author is John Jacob Muli). Commit messages end with the `[7.6]` tag, matching branch `feat/7.6-map-select`.
- **Source of truth for values:** `.local/README.md` (handoff component) + the design spec `docs/superpowers/specs/2026-07-05-map-select-hifi-design.md`. The corrected region↔stage mapping in Task 1 is authoritative (fixes a prior shuffle bug).
- **Region metadata lives in exactly one place:** `map_manager.gd` `REGIONS`. The generator, UI, and markers all read from it.

---

### Task 1: Region metadata + corrected stage mapping (data layer)

Replace the thin `REGIONS` dict with the full hi-fi metadata and fix the Central/Visayas/Mindanao stage shuffle. This is the single source of truth every later task reads.

**Files:**
- Modify: `scenes/ui/map_select/map_manager.gd:5-34` (`BASE_COLOR` const + `REGIONS` dict)
- Create: `tests/test_map_data.gd`

**Interfaces:**
- Produces: `Data.REGIONS` — a `Dictionary` keyed by macro-region id. Each value has keys `index:int`, `display:String` (UPPERCASE region name), `base:Color`, `neon:Color`, `neon_stroke:Color`, `fighter:String`, `stage:String` (res:// path to `.tres`), `stage_label:String` (UPPERCASE preview name), `story:String`.
- Produces: `Data.REGION_ORDER: Array[String]` — the 5 ids in index order (1..5), for stable iteration/labeling.
- Produces: `Data.INK := Color("#0a0904")` and `Data.UNDERSIDE := Color("#2a2612")` (shared bake/paint tokens).
- Consumes: nothing.
- `BASE_COLOR` is **removed** — each region now carries its own `base`. Later tasks that referenced `Data.BASE_COLOR` (generator, tests) are updated in their own tasks.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_data.gd`:

```gdscript
extends SceneTree
## Validates REGIONS metadata + the corrected region->stage mapping (regression
## for the Central/Visayas/Mindanao shuffle bug). Pure data — no scene needed.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

## The authoritative mapping from the handoff (.local/README.md META table).
const EXPECTED := {
	"NorthernLuzon": {"index": 1, "display": "NORTHERN LUZON", "fighter": "BUNO",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres"},
	"CentralLuzon":  {"index": 2, "display": "CENTRAL LUZON", "fighter": "DIRTY BOXING",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres"},
	"SouthernLuzon": {"index": 3, "display": "SOUTHERN LUZON", "fighter": "ARNIS",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres"},
	"Visayas":       {"index": 4, "display": "VISAYAS", "fighter": "SIKARAN",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres"},
	"Mindanao":      {"index": 5, "display": "MINDANAO", "fighter": "SEPAK TAKRAW",
		"stage": "res://stages/beach_court/beach_court_data.tres"},
}

func _init() -> void:
	ok(Data.REGIONS.size() == 5, "exactly 5 regions (got %d)" % Data.REGIONS.size())
	ok(Data.REGION_ORDER.size() == 5, "REGION_ORDER has 5 ids")

	var required := ["index", "display", "base", "neon", "neon_stroke",
		"fighter", "stage", "stage_label", "story"]
	for gid in EXPECTED:
		ok(Data.REGIONS.has(gid), "region present: " + gid)
		if not Data.REGIONS.has(gid):
			continue
		var r: Dictionary = Data.REGIONS[gid]
		for key in required:
			ok(r.has(key), "%s has key %s" % [gid, key])
		# corrected mapping (regression guard)
		ok(r["index"] == EXPECTED[gid]["index"], "%s index" % gid)
		ok(r["display"] == EXPECTED[gid]["display"], "%s display" % gid)
		ok(r["fighter"] == EXPECTED[gid]["fighter"], "%s fighter" % gid)
		ok(r["stage"] == EXPECTED[gid]["stage"], "%s stage path (shuffle regression)" % gid)
		ok(ResourceLoader.exists(r["stage"]), "%s stage .tres exists on disk" % gid)
		ok(r["base"] is Color and r["neon"] is Color and r["neon_stroke"] is Color,
			"%s colors are Color" % gid)
		ok((r["story"] as String).length() > 0, "%s has non-empty story" % gid)

	# REGION_ORDER is index-sorted and matches keys
	for i in Data.REGION_ORDER.size():
		var gid: String = Data.REGION_ORDER[i]
		ok(Data.REGIONS.has(gid), "REGION_ORDER[%d] is a real region" % i)
		ok(Data.REGIONS[gid]["index"] == i + 1, "REGION_ORDER[%d] index == %d" % [i, i + 1])

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_data.gd`
Expected: FAIL — REGIONS lacks `index`/`base`/`neon_stroke`/`fighter`/`stage_label`/`story`, and current Central/Visayas/Mindanao stage paths are shuffled (Central→heritage_plaza, Visayas→beach_court, Mindanao→barangay_ring). Non-zero exit.

- [ ] **Step 3: Rewrite the metadata block**

In `scenes/ui/map_select/map_manager.gd`, replace lines 5–34 (the `BASE_COLOR` const through the end of the `REGIONS` dict) with the block below.

> **Compile-safety note:** the old hover code further down the file (rewritten only in Task 6) still references `BASE_COLOR`. GDScript compiles the whole file, so we keep a **temporary** `BASE_COLOR` alias here to avoid breaking Tasks 1–5. Task 6 deletes it along with the old block.

```gdscript
## Shared ink + underside tokens (also read by the @tool generator).
const INK := Color("#0a0904")
const UNDERSIDE := Color("#2a2612")
const BASE_COLOR := Color("#343d46")  # TEMPORARY — old hover block still refs it; removed in Task 6

## adm1_pcode -> macro-region id. Verified against .local/philippines_optimized.json.
const GROUPS := {
	"PH01": "NorthernLuzon", "PH02": "NorthernLuzon", "PH14": "NorthernLuzon",
	"PH03": "CentralLuzon", "PH13": "CentralLuzon",
	"PH04": "SouthernLuzon", "PH17": "SouthernLuzon", "PH05": "SouthernLuzon",
	"PH06": "Visayas", "PH07": "Visayas", "PH08": "Visayas",
	"PH09": "Mindanao", "PH10": "Mindanao", "PH11": "Mindanao",
	"PH12": "Mindanao", "PH16": "Mindanao", "PH19": "Mindanao",
}

## macro-region id -> full hi-fi metadata. THE single source of truth (generator,
## UI, and markers all read this). Stage mapping matches the handoff table exactly.
const REGIONS := {
	"NorthernLuzon": {
		"index": 1, "display": "NORTHERN LUZON",
		"base": Color("#3f6f92"), "neon": Color("#34b0ff"), "neon_stroke": Color("#bfe6ff"),
		"fighter": "BUNO",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres",
		"stage_label": "MOUNTAIN FESTIVAL GROUNDS",
		"story": "Highland grapplers forged in the festivals of the Cordillera ranges."},
	"CentralLuzon": {
		"index": 2, "display": "CENTRAL LUZON",
		"base": Color("#a8432f"), "neon": Color("#ff5a3c"), "neon_stroke": Color("#ffc7ba"),
		"fighter": "DIRTY BOXING",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres",
		"stage_label": "BARANGAY BOXING RING",
		"story": "Street-hardened brawlers trading blows in the barangay rings."},
	"SouthernLuzon": {
		"index": 3, "display": "SOUTHERN LUZON",
		"base": Color("#5c8038"), "neon": Color("#84e23c"), "neon_stroke": Color("#d9ffb2"),
		"fighter": "ARNIS",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres",
		"stage_label": "BAHAY KUBO TRAINING YARD",
		"story": "Stick-and-blade masters drilling in the southern training yards."},
	"Visayas": {
		"index": 4, "display": "VISAYAS",
		"base": Color("#6b4a9c"), "neon": Color("#b154ff"), "neon_stroke": Color("#e2c2ff"),
		"fighter": "SIKARAN",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres",
		"stage_label": "HERITAGE PLAZA",
		"story": "Sikaran was born from freedom and resilience in the island heartland."},
	"Mindanao": {
		"index": 5, "display": "MINDANAO",
		"base": Color("#c0982f"), "neon": Color("#ffd23a"), "neon_stroke": Color("#fff1b0"),
		"fighter": "SEPAK TAKRAW",
		"stage": "res://stages/beach_court/beach_court_data.tres",
		"stage_label": "BEACH COURT AT DUSK",
		"story": "Airborne acrobats who settle every score on the dusk-lit shore."},
}

## Region ids in index order (1..5) — stable iteration + labeling.
const REGION_ORDER: Array[String] = [
	"NorthernLuzon", "CentralLuzon", "SouthernLuzon", "Visayas", "Mindanao"]
```

> Note: the old runtime hover code below this block is fully rewritten in Task 6. Leaving the temporary `BASE_COLOR` alias in place keeps the file compiling; do not touch the old hover functions in this task.

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_data.gd`
Expected: PASS — `NN checks, 0 failures`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_manager.gd tests/test_map_data.gd
git commit -m "feat(map): full region metadata + corrected stage mapping [7.6]"
```

---

### Task 2: Source Anton + Oswald fonts

Add the display/body TTFs the hi-fi UI needs, with Godot `.import` sidecars generated, so Task 7 can load them.

**Files:**
- Create: `art/fonts/Anton-Regular.ttf`, `art/fonts/Oswald-VariableFont_wght.ttf`
- Create: `art/fonts/OFL-Anton.txt`, `art/fonts/OFL-Oswald.txt`
- Create (generated): `art/fonts/Anton-Regular.ttf.import`, `art/fonts/Oswald-VariableFont_wght.ttf.import`

**Interfaces:**
- Produces: `res://art/fonts/Anton-Regular.ttf` (display) and `res://art/fonts/Oswald-VariableFont_wght.ttf` (body), loadable via `load(...)` as `FontFile`.
- Consumes: nothing.

- [ ] **Step 1: Download the OFL fonts**

```bash
cd /home/jacob/LOTA/art/fonts
curl -fL -o Anton-Regular.ttf https://github.com/google/fonts/raw/main/ofl/anton/Anton-Regular.ttf
curl -fL -o Oswald-VariableFont_wght.ttf "https://github.com/google/fonts/raw/main/ofl/oswald/Oswald%5Bwght%5D.ttf"
curl -fL -o OFL-Anton.txt https://github.com/google/fonts/raw/main/ofl/anton/OFL.txt
curl -fL -o OFL-Oswald.txt https://github.com/google/fonts/raw/main/ofl/oswald/OFL.txt
```

- [ ] **Step 2: Verify the files are real TTFs**

Run: `file /home/jacob/LOTA/art/fonts/Anton-Regular.ttf /home/jacob/LOTA/art/fonts/Oswald-VariableFont_wght.ttf`
Expected: both report `TrueType Font data` (or `OpenType`). Sizes > 40 KB. If `curl` failed (HTML/empty), the network is blocked — STOP and report to the user; do not fabricate a font. Fallback path: reuse `res://art/fonts/BebasNeue-Regular.ttf` for both and note the deviation (Task 7 uses named consts `DISPLAY_FONT` / `BODY_FONT` so only two paths change).

- [ ] **Step 3: Generate Godot import sidecars**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --import`
Expected: exits after importing; `art/fonts/Anton-Regular.ttf.import` and `art/fonts/Oswald-VariableFont_wght.ttf.import` now exist.

- [ ] **Step 4: Verify Godot can load them headlessly**

Create throwaway check `res://scripts/dev/_fontcheck.gd`:

```gdscript
extends SceneTree
func _init() -> void:
	var a := load("res://art/fonts/Anton-Regular.ttf")
	var o := load("res://art/fonts/Oswald-VariableFont_wght.ttf")
	print("anton=", a != null, " oswald=", o != null)
	quit(0 if a != null and o != null else 1)
```

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://scripts/dev/_fontcheck.gd`
Expected: `anton=true oswald=true`, exit 0. Then delete the throwaway: `rm /home/jacob/LOTA/scripts/dev/_fontcheck.gd`.

- [ ] **Step 5: Commit**

```bash
git add art/fonts/Anton-Regular.ttf art/fonts/Oswald-VariableFont_wght.ttf \
        art/fonts/Anton-Regular.ttf.import art/fonts/Oswald-VariableFont_wght.ttf.import \
        art/fonts/OFL-Anton.txt art/fonts/OFL-Oswald.txt
git commit -m "chore(fonts): add Anton + Oswald (OFL) for map-select hi-fi UI [7.6]"
```

---

### Task 3: Generator — extruded 3-pass bake + per-region color + centroid

Rework the baker so each region renders as a cel-shaded extruded landmass (cast shadow → underside wall → top face) in its own base color, and stores its area-weighted centroid as node metadata for marker placement.

**Files:**
- Modify: `scenes/ui/map_select/map_generator.gd` (constants block `108-113`; `_bake_region_into` `172-216`; add centroid helper)
- Modify: `tests/test_map_baker.gd` (expectations for the new `Visual/Shadow`, `Visual/Underside`, `Visual/Top` structure + centroid meta)

**Interfaces:**
- Consumes: `Data.REGIONS[gid]["base"]`, `Data.INK`, `Data.UNDERSIDE` (Task 1).
- Produces: baked region tree — `region (Node2D, name=gid, meta "centroid":Vector2)` → `Visual (Node2D)` → three child `Node2D`s named `Shadow`, `Underside`, `Top`. `Top` holds the interactive/recolorable `Polygon2D` (fill=base) + `Line2D` (stroke=INK) per ring — this is the hit-test + recolor layer. `Underside` holds dark `Polygon2D` + thick `Line2D`, offset by `SIDE_EXTRUDE`. `Shadow` holds one dark-transparent `Polygon2D` per ring offset by `SHADOW_OFFSET`, no stroke.
- Produces static helper `Gen.polygon_centroid(pts: PackedVector2Array) -> Vector2` and `Gen.region_centroid(rings: Array) -> Vector2`.

- [ ] **Step 1: Write the failing test — update `tests/test_map_baker.gd`**

Replace the body from line 34 (`# each region has a Visual…`) through line 60 (the base-fill check) with:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_baker.gd`
Expected: FAIL — current bake has flat `Visual` children (no `Shadow`/`Underside`/`Top`), no centroid meta, and fills use the removed `BASE_COLOR`.

- [ ] **Step 3: Update the generator constants**

In `scenes/ui/map_select/map_generator.gd`, replace the constant `OUTLINE_WIDTH` line (`111`) and add extrusion tokens. Replace lines 111–113 with:

```gdscript
const TOP_STROKE := 7.0        # top-face ink stroke (graphic-novel)
const SIDE_STROKE := 9.0       # underside wall stroke
const SIMPLIFY_EPS := 1.5      # Douglas-Peucker tolerance (projected px)
const OUTLINE_SHADER := "res://scenes/ui/map_select/outline.gdshader"
const SIDE_EXTRUDE := Vector2(0.0, 10.0)   # underside wall depth (pre-tilt +Y)
const SHADOW_OFFSET := Vector2(7.0, 12.0)  # idle hard cast-shadow offset
const SHADOW_COLOR := Color(4.0 / 255.0, 3.0 / 255.0, 1.0 / 255.0, 0.9)
```

- [ ] **Step 4: Add the centroid helpers**

Add these static functions after `ring_area` (after line 105):

```gdscript
## Shoelace-weighted centroid of one ring. Falls back to vertex mean for
## degenerate (near-zero-area) rings.
static func polygon_centroid(pts: PackedVector2Array) -> Vector2:
	var n := pts.size()
	if n < 3:
		return _mean(pts)
	var a := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in n:
		var j := (i + 1) % n
		var cross := pts[i].x * pts[j].y - pts[j].x * pts[i].y
		a += cross
		cx += (pts[i].x + pts[j].x) * cross
		cy += (pts[i].y + pts[j].y) * cross
	if absf(a) < 0.000001:
		return _mean(pts)
	a *= 0.5
	return Vector2(cx / (6.0 * a), cy / (6.0 * a))

static func _mean(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	var s := Vector2.ZERO
	for p in pts:
		s += p
	return s / pts.size()

## Area-weighted centroid across a region's rings (biggest landmass dominates).
static func region_centroid(rings: Array) -> Vector2:
	var total := 0.0
	var acc := Vector2.ZERO
	for pts in rings:
		var area: float = ring_area(pts)
		acc += polygon_centroid(pts) * area
		total += area
	return acc / total if total > 0.0 else Vector2.ZERO
```

- [ ] **Step 5: Rewrite `_bake_region_into`**

Replace the whole `_bake_region_into` function (lines 172–216) with:

```gdscript
func _bake_region_into(target: Node2D, gid: String, rings: Array, owner_root: Node) -> void:
	# Region root is a plain Node2D — hit-testing is geometric at runtime
	# (map_manager), so no CollisionPolygon2D / convex decomposition.
	var region := Node2D.new()
	region.name = gid
	target.add_child(region)
	if owner_root:
		region.set_owner(owner_root)
	region.set_meta("centroid", region_centroid(rings))

	var visual := Node2D.new()
	visual.name = "Visual"
	region.add_child(visual)
	if owner_root:
		visual.set_owner(owner_root)

	var shadow := _layer(visual, "Shadow", owner_root)
	var underside := _layer(visual, "Underside", owner_root)
	var top := _layer(visual, "Top", owner_root)

	var shader: Shader = load(OUTLINE_SHADER) if ResourceLoader.exists(OUTLINE_SHADER) else null
	var base: Color = Data.REGIONS[gid]["base"]

	for pts in rings:
		# 1) hard cast shadow (behind), offset, no stroke
		_add_poly(shadow, _offset(pts, SHADOW_OFFSET), SHADOW_COLOR, null, owner_root)
		# 2) underside wall, offset down, dark fill + thick dark stroke
		var under_pts := _offset(pts, SIDE_EXTRUDE)
		_add_poly(underside, under_pts, Data.UNDERSIDE, null, owner_root)
		_add_stroke(underside, under_pts, Data.INK, SIDE_STROKE, owner_root)
		# 3) top face — the interactive/recolorable layer
		_add_poly(top, pts, base, shader, owner_root)
		_add_stroke(top, pts, Data.INK, TOP_STROKE, owner_root)

## Create + own a named Node2D layer under `parent`.
func _layer(parent: Node2D, layer_name: String, owner_root: Node) -> Node2D:
	var n := Node2D.new()
	n.name = layer_name
	parent.add_child(n)
	if owner_root:
		n.set_owner(owner_root)
	return n

static func _offset(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out

func _add_poly(parent: Node2D, pts: PackedVector2Array, color: Color,
		shader: Shader, owner_root: Node) -> void:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = color
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		poly.material = mat
	parent.add_child(poly)
	if owner_root:
		poly.set_owner(owner_root)

func _add_stroke(parent: Node2D, pts: PackedVector2Array, color: Color,
		width: float, owner_root: Node) -> void:
	var line := Line2D.new()
	var closed := PackedVector2Array(pts)
	if closed.size() > 0:
		closed.append(closed[0])
	line.points = closed
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)
	if owner_root:
		line.set_owner(owner_root)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_baker.gd`
Expected: PASS — `NN checks, 0 failures`.

Run the projection-math regression (unchanged API): `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_generator.gd`
Expected: PASS (this task did not touch `project`/`compute_bounds`/`simplify`).

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/map_select/map_generator.gd tests/test_map_baker.gd
git commit -m "feat(map): extruded 3-pass bake (shadow/underside/top) + centroid [7.6]"
```

---

### Task 4: MapPlane affine tilt + plane-local hit-testing

Parent the regions under a `MapPlane` `Node2D` carrying the static tilt, and point the manager's region lookup at it. Hit-testing already inverse-maps through ancestors via `to_local`, so it "just works" once regions live under the tilted plane — this task adds the lookup redirection and a regression test proving an interior point still resolves through the tilt.

**Files:**
- Modify: `scenes/ui/map_select/map_manager.gd` — add `map_plane_path` export + `_regions()` lookup under the plane; add static `tilt_transform`.
- Modify: `tests/test_map_manager.gd` — build regions under a `MapPlane`, apply the tilt, assert hit-testing.

**Interfaces:**
- Consumes: `Data.REGIONS` / `Data.REGION_ORDER`.
- Produces: `@export var map_plane_path: NodePath`; `_regions()` returns the region `Node2D`s found under the node at `map_plane_path` (falling back to `self` for legacy/flat trees). Static `Mgr.tilt_transform(center: Vector2, rot_deg: float, scale_y: float) -> Transform2D` — rotates by `rot_deg` and squashes Y by `scale_y`, pivoting about `center`.
- Produces: `Mgr.TILT_ROT_DEG := -20.0` and `Mgr.TILT_SCALE_Y := cos(deg_to_rad(49.0))` constants (used by the builder in Task 9).

- [ ] **Step 1: Write the failing test — update `tests/test_map_manager.gd`**

Replace lines 51–62 (the build + region lookup) with a version that nests regions under a `MapPlane` and applies the tilt:

```gdscript
	# Build regions under a tilted MapPlane, then run the manager against it.
	var root: Node2D = Mgr.new()
	get_root().add_child(root)
	var plane := Node2D.new()
	plane.name = "MapPlane"
	root.add_child(plane)
	root.map_plane_path = NodePath("MapPlane")
	# bake region Node2Ds as children of the plane
	var gen: Node2D = Gen.new()
	root.add_child(gen)
	gen.build_into(plane)
	gen.free()
	# apply the affine tilt about the archipelago centre
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in root._regions():
		var c: Vector2 = r.get_meta("centroid")
		lo = lo.min(c); hi = hi.max(c)
	var centre := (lo + hi) * 0.5
	plane.transform = Mgr.tilt_transform(centre, Mgr.TILT_ROT_DEG, Mgr.TILT_SCALE_Y)

	var region: Node2D = plane.get_node("Visayas")
	var visual: Node2D = region.get_node("Visual")
```

Then update the hover/hit assertions below it: the neon check now targets `Visual/Top`, and the interior-point helper reads a `Top` polygon. Replace the block from `# hover in recolors…` (old lines 64–84) with:

```gdscript
	# an interior point of a Top polygon, taken through the tilt, resolves to the region
	var top: Node2D = region.get_node("Visual/Top")
	var poly: Polygon2D = null
	for v in top.get_children():
		if v is Polygon2D:
			poly = v
			break
	ok(poly != null, "Visayas has a Top polygon")

	ok(root._region_at(Vector2(-5000, -5000)) == null, "_region_at outside map returns null")
	var inside = _interior_point(poly)  # untyped: may be null (plane-space point)
	ok(inside != null, "found an interior sample point in Visayas")
	if inside != null:
		# poly points are in plane space; map plane-space -> global for the query
		var global_pt: Vector2 = plane.to_global(inside)
		ok(root._region_at(global_pt) == region, "_region_at interior point (through tilt) -> Visayas")
```

Remove the old `_apply_hover_in/out` and `_select`/`region_selected` assertions from this test (those move to Task 6's test). Keep the `_interior_point` helper and the final `print`/`quit`.

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_manager.gd`
Expected: FAIL — `map_plane_path`, `_regions()` under a plane, `tilt_transform`, `TILT_ROT_DEG`, and `TILT_SCALE_Y` don't exist yet.

- [ ] **Step 3: Add the tilt API + plane lookup to the manager**

In `scenes/ui/map_select/map_manager.gd`, add near the top (after the `REGION_ORDER` const from Task 1):

```gdscript
## Static affine tilt (comic-book diagonal + faked elevation). No 3D.
const TILT_ROT_DEG := -20.0
const TILT_SCALE_Y := 0.6560590   # cos(49°)

@export var map_plane_path: NodePath

## T(p) = centre + R(rot) * S(1, scale_y) * (p - centre). Squash first, then rotate.
static func tilt_transform(centre: Vector2, rot_deg: float, scale_y: float) -> Transform2D:
	var pivot_in := Transform2D(0.0, -centre)
	var squash := Transform2D(Vector2(1.0, 0.0), Vector2(0.0, scale_y), Vector2.ZERO)
	var rot := Transform2D(deg_to_rad(rot_deg), Vector2.ZERO)
	var pivot_out := Transform2D(0.0, centre)
	return pivot_out * rot * squash * pivot_in
```

Replace `_regions()` (old lines 52–58) with a version that looks under the plane:

```gdscript
## Node holding the tilted region children (falls back to self for flat trees).
func _plane() -> Node:
	if not map_plane_path.is_empty():
		var p := get_node_or_null(map_plane_path)
		if p != null:
			return p
	return self

## The 5 baked region roots (plain Node2D, named by macro-region id).
func _regions() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var plane := _plane()
	for gid in REGIONS:
		var r := plane.get_node_or_null(NodePath(gid)) as Node2D
		if r != null:
			out.append(r)
	return out
```

> `_region_at` already uses `region.to_local(global_pos)`, whose global transform now includes the `MapPlane` tilt — no change needed there beyond Task 6's `Visual/Top` retargeting.

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_manager.gd`
Expected: FAIL still — `_region_at` iterates `visual.get_children()` for `Polygon2D`, but polygons now live under `Visual/Top`/`Underside`/`Shadow`. This is fixed in Task 6. For an isolated green here, temporarily change `_region_at`'s inner loop to search `visual.get_node("Top").get_children()`; Task 6 formalizes it. Re-run → Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_manager.gd tests/test_map_manager.gd
git commit -m "feat(map): MapPlane affine tilt + plane-local region lookup [7.6]"
```

---

### Task 5: Background — dusk-ocean shader

Create the full-bleed painterly sunset shader and prove it compiles + the ColorRect boots.

**Files:**
- Create: `scenes/ui/map_select/background.gdshader`
- Create: `tests/test_background_shader.gd`

**Interfaces:**
- Produces: `res://scenes/ui/map_select/background.gdshader` — a `canvas_item` shader that paints the dusk-ocean gradient, sun glow, horizon humps, water sheen, and vignette using only `UV` (0..1 across the ColorRect). No uniforms required.
- Consumes: nothing. (Task 9 attaches it to a `ColorRect` sized 1280×720 at z −10.)

- [ ] **Step 1: Write the failing test**

Create `tests/test_background_shader.gd`:

```gdscript
extends SceneTree
## The background shader must exist, compile clean, and drive a ColorRect.

const PATH := "res://scenes/ui/map_select/background.gdshader"

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	ok(ResourceLoader.exists(PATH), "background.gdshader exists")
	var shader: Shader = load(PATH) if ResourceLoader.exists(PATH) else null
	ok(shader != null and shader is Shader, "loads as Shader")
	if shader:
		var rect := ColorRect.new()
		rect.size = Vector2(1280, 720)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		rect.material = mat
		get_root().add_child(rect)  # would print a SHADER ERROR to stderr if it failed to compile
		ok(rect.material != null, "ColorRect accepts the shader material")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_background_shader.gd`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the shader**

Create `scenes/ui/map_select/background.gdshader`:

```glsl
shader_type canvas_item;
// Dusk-ocean backdrop for Map Select. Reproduces the handoff Layer-1 stack in a
// single fragment pass over UV (0..1). No textures, no uniforms — pure gradient art.

// linear-gradient(180deg) stops from the handoff, top(0)->bottom(1).
vec3 sky_ocean(float y) {
	vec3 c;
	if (y < 0.15)      c = mix(vec3(0.109,0.074,0.051), vec3(0.498,0.258,0.109), y / 0.15);
	else if (y < 0.27) c = mix(vec3(0.498,0.258,0.109), vec3(0.752,0.439,0.121), (y - 0.15) / 0.12);
	else if (y < 0.37) c = mix(vec3(0.752,0.439,0.121), vec3(0.690,0.407,0.164), (y - 0.27) / 0.10);
	else if (y < 0.49) c = mix(vec3(0.690,0.407,0.164), vec3(0.360,0.356,0.235), (y - 0.37) / 0.12);
	else if (y < 0.60) c = mix(vec3(0.360,0.356,0.235), vec3(0.133,0.321,0.360), (y - 0.49) / 0.11);
	else if (y < 0.74) c = mix(vec3(0.133,0.321,0.360), vec3(0.074,0.223,0.278), (y - 0.60) / 0.14);
	else if (y < 0.90) c = mix(vec3(0.074,0.223,0.278), vec3(0.039,0.109,0.149), (y - 0.74) / 0.16);
	else               c = mix(vec3(0.039,0.109,0.149), vec3(0.027,0.066,0.094), (y - 0.90) / 0.10);
	return c;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = sky_ocean(uv.y);

	// warm sun glow ellipse at (50%, 30%) — radial-gradient(120% 78%).
	vec2 gp = (uv - vec2(0.5, 0.30)) / vec2(0.60, 0.39);
	float glow = clamp(1.0 - length(gp), 0.0, 1.0);
	col += vec3(1.0, 0.690, 0.329) * glow * glow * 0.55;

	// three distant island humps on the horizon (~top third).
	float humps = 0.0;
	humps = max(humps, smoothstep(0.11, 0.10, distance(uv, vec2(0.20, 0.355)) * vec2(1.0, 5.0).x));
	// approximate humps as squashed discs
	humps = max(humps, 1.0 - smoothstep(0.0, 1.0, length((uv - vec2(0.20, 0.360)) / vec2(0.09, 0.03))));
	humps = max(humps, 1.0 - smoothstep(0.0, 1.0, length((uv - vec2(0.65, 0.355)) / vec2(0.055, 0.032))));
	humps = max(humps, 1.0 - smoothstep(0.0, 1.0, length((uv - vec2(0.90, 0.360)) / vec2(0.10, 0.036))));
	humps *= step(uv.y, 0.375);  // only above the horizon line
	col = mix(col, vec3(0.145, 0.117, 0.105), humps * 0.5);

	// faint water sheen streaks (screen-ish) from ~46% down.
	if (uv.y > 0.46) {
		float streak = step(0.5, fract(uv.y * 720.0 / 40.0)) * 0.03;
		col += vec3(1.0, 0.768, 0.470) * streak * (uv.y - 0.46);
	}

	// vignette: transparent centre -> dark edges (radial 130% 100% at 50% 46%).
	vec2 vp = (uv - vec2(0.5, 0.46)) / vec2(0.65, 0.5);
	float vig = smoothstep(0.55, 1.0, length(vp));
	col = mix(col, vec3(0.015, 0.039, 0.054), vig * 0.72);

	COLOR = vec4(col, 1.0);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_background_shader.gd`
Expected: PASS — `N checks, 0 failures`, and NO `SHADER ERROR` lines in stderr. If a `SHADER ERROR` appears, fix the reported line and re-run.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/background.gdshader tests/test_background_shader.gd
git commit -m "feat(map): dusk-ocean background shader [7.6]"
```

---

### Task 6: Manager — hover/select/confirm state machine

Rework the runtime controller for the hi-fi interaction model: hover paints gold, click selects (paints neon, enables confirm), confirm shows the ribbon then navigates. Drive the UI + markers layers through node refs. Split the old combined `_select` (which selected AND navigated) into `_select` (state only) and `confirm` (navigate).

**Files:**
- Modify: `scenes/ui/map_select/map_manager.gd` — replace the hover/select block (`36-154`) with the new state machine; add `ui_path` / `markers_path` exports; wire `_ready`.
- Modify: `tests/test_map_manager.gd` — add state-machine assertions (append to the file built in Task 4).

**Interfaces:**
- Consumes: `Data.REGIONS`, `_regions()`, `_plane()`, the `Visual/Top` bake layer (Task 3), the UI methods `set_state(Dictionary)` + `show_ribbon(String)` and signal `confirm_pressed` (Task 7), the markers method `set_color(String, Color)` (Task 8).
- Produces: `signal region_selected(region_name: String, stage_name: String)` (emitted on **confirm**, not on click). Methods exercised by tests: `_apply_hover_in(region)`, `_apply_hover_out(region)`, `_select(region)`, `confirm()`; state vars `_hovered`, `_selected` (region `Node2D` or `null`).
- Produces: hover/select tokens `HOVER_FILL := Color("#a7a24b")`, `HOVER_STROKE := Color("#ffd24a")`, `HOVER_ACCENT := Color("#ffcf3f")`, `IDLE_ACCENT := Color("#4a5058")`.

- [ ] **Step 1: Write the failing test — append to `tests/test_map_manager.gd`**

Before the final `print(...)`/`quit(...)`, add a headless UI/markers double and state assertions:

```gdscript
	# --- state machine: hover paints gold, select paints neon, confirm emits ---
	var ui := _StubUI.new()
	var markers := _StubMarkers.new()
	root.add_child(ui)
	root.add_child(markers)
	root.ui_path = root.get_path_to(ui)
	root.markers_path = root.get_path_to(markers)

	root._apply_hover_in(region)
	ok(poly.color == Mgr.HOVER_FILL, "hover paints top face gold fill")
	ok(ui.last_state.get("kicker", "") == "HOVER · SCOUTING", "UI kicker -> hover")
	root._apply_hover_out(region)
	ok(poly.color == Data.REGIONS["Visayas"]["base"], "hover-out reverts to base")

	root.region_selected.connect(func(n, s): emitted.append([n, s]))
	root._select(region)
	ok(poly.color == Data.REGIONS["Visayas"]["neon"], "select paints top face neon")
	ok(ui.last_state.get("confirm_enabled", false) == true, "select enables confirm")
	ok(emitted.size() == 0, "select does NOT emit region_selected yet")

	root.confirm()
	ok(emitted.size() == 1, "confirm emits region_selected once")
	if emitted.size() == 1:
		ok(emitted[0][0] == "VISAYAS", "emitted display == VISAYAS")
		ok(emitted[0][1] == Data.REGIONS["Visayas"]["stage"], "emitted stage path correct")
	ok(ui.ribbon_shown == "HERITAGE PLAZA", "confirm shows ribbon with stage_label")
```

And add the stub classes at the top of the file (after the existing `const` lines):

```gdscript
class _StubUI extends CanvasLayer:
	signal confirm_pressed
	var last_state := {}
	var ribbon_shown := ""
	func set_state(d: Dictionary) -> void: last_state = d
	func show_ribbon(stage_label: String) -> void: ribbon_shown = stage_label

class _StubMarkers extends Node2D:
	var colors := {}
	func set_color(gid: String, c: Color) -> void: colors[gid] = c
```

Also add `var emitted := []` near the other test vars if not already present.

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_manager.gd`
Expected: FAIL — `ui_path`, `markers_path`, the new painting colors, split `_select`/`confirm`, and `set_state`/`show_ribbon` wiring don't exist.

- [ ] **Step 3: Replace the hover/select block in `map_manager.gd`**

Also delete the temporary `const BASE_COLOR := Color("#343d46")` line added in Task 1 (no longer referenced once the block below replaces the old hover code). Then replace everything from the `signal region_selected` line through the end of the file (old lines 36–154) with:

```gdscript
signal region_selected(region_name: String, stage_name: String)

const HOVER_LIFT := -15.0
const TOP_STROKE := 7.0
const HOVER_FILL := Color("#a7a24b")
const HOVER_STROKE := Color("#ffd24a")
const HOVER_ACCENT := Color("#ffcf3f")
const IDLE_ACCENT := Color("#4a5058")

@export var ui_path: NodePath
@export var markers_path: NodePath

var _hovered: Node2D = null
var _selected: Node2D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_unhandled_input(true)
	var ui := _ui()
	if ui and ui.has_signal("confirm_pressed"):
		ui.confirm_pressed.connect(confirm)
	_push_ui(null)  # STANDBY

func _ui() -> Node:
	return get_node_or_null(ui_path) if not ui_path.is_empty() else null

func _markers() -> Node:
	return get_node_or_null(markers_path) if not markers_path.is_empty() else null

func _top_of(region: Node2D) -> Node2D:
	return region.get_node_or_null("Visual/Top") as Node2D

func _visual_of(region: Node2D) -> Node2D:
	return region.get_node_or_null("Visual") as Node2D

## First region whose Top-face polygons contain global_pos. Tested in region-local
## space (which includes the MapPlane tilt via to_local), so neither the tilt nor
## the hover lift shifts the hit area.
func _region_at(global_pos: Vector2) -> Node2D:
	for region in _regions():
		var top := _top_of(region)
		if top == null:
			continue
		var local := region.to_local(global_pos)
		for child in top.get_children():
			if child is Polygon2D and Geometry2D.is_point_in_polygon(local, child.polygon):
				return region
	return null

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseMotion:
		_update_hover(get_global_mouse_position())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var region := _region_at(get_global_mouse_position())
		if region != null:
			_select(region)

func _update_hover(global_pos: Vector2) -> void:
	var region := _region_at(global_pos)
	if region == _hovered:
		return
	if _hovered != null:
		_apply_hover_out(_hovered)
	_hovered = region
	if _hovered != null:
		_apply_hover_in(_hovered)
	else:
		_push_ui(_selected)  # fall back to selected (or STANDBY)

## Paint a region's Top face + its marker. `state` in {"base","hover","select"}.
func _paint(region: Node2D, state: String) -> void:
	var top := _top_of(region)
	if top == null:
		return
	var gid := String(region.name)
	var meta: Dictionary = REGIONS[gid]
	var fill: Color
	var stroke: Color
	match state:
		"hover":
			fill = HOVER_FILL; stroke = HOVER_STROKE
		"select":
			fill = meta["neon"]; stroke = meta["neon_stroke"]
		_:
			fill = meta["base"]; stroke = INK
	for child in top.get_children():
		if child is Polygon2D:
			child.color = fill
		elif child is Line2D:
			child.default_color = stroke
	var markers := _markers()
	if markers and markers.has_method("set_color"):
		var dot: Color = HOVER_STROKE if state == "hover" else \
			(meta["neon"] if state == "select" else meta["base"])
		markers.set_color(gid, dot)

func _apply_hover_in(region: Node2D) -> void:
	region.z_index = 1
	_paint(region, "hover")
	var visual := _visual_of(region)
	if visual:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position:y", HOVER_LIFT, 0.22)
	_push_ui(region)

func _apply_hover_out(region: Node2D) -> void:
	region.z_index = 0
	_paint(region, "select" if region == _selected else "base")
	var visual := _visual_of(region)
	if visual:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
		tw.tween_property(visual, "position:y", 0.0, 0.22)

func _select(region: Node2D) -> void:
	if _selected != null and _selected != region:
		_paint(_selected, "base")
	_selected = region
	_paint(region, "select")
	_push_ui(region)

## Build the UI state dict for the region driving the panel (hovered has priority;
## else selected; else STANDBY when null).
func _push_ui(region: Node2D) -> void:
	var ui := _ui()
	if ui == null or not ui.has_method("set_state"):
		return
	var hovering := _hovered != null
	var d := {}
	if region == null:
		d = {"kicker": "STANDBY", "accent": IDLE_ACCENT, "region_name": "SELECT YOUR ARENA",
			"region_no": "", "fighter": "—", "stage": "—",
			"story": "Hover a region to scout its stage and fighter. Click a landmass to lock your pick, then confirm.",
			"fighter_label": _selected_fighter(), "confirm_enabled": _selected != null}
	else:
		var gid := String(region.name)
		var m: Dictionary = REGIONS[gid]
		var accent: Color = HOVER_ACCENT if hovering else m["neon"]
		var kicker := "HOVER · SCOUTING" if hovering else "LOCKED IN"
		d = {"kicker": kicker, "accent": accent, "region_name": m["display"],
			"region_no": "(REGION %d)" % m["index"], "fighter": m["fighter"],
			"stage": m["stage_label"], "story": m["story"],
			"fighter_label": _selected_fighter(), "confirm_enabled": _selected != null}
	ui.set_state(d)

func _selected_fighter() -> String:
	if _selected == null:
		return "[Selected Fighter Name]"
	return REGIONS[String(_selected.name)]["fighter"]

## Commit the current selection: show the ribbon, emit, stash stage, navigate.
func confirm() -> void:
	if _selected == null:
		return
	var gid := String(_selected.name)
	var meta: Dictionary = REGIONS[gid]
	var stage_path: String = meta["stage"]
	region_selected.emit(meta["display"], stage_path)
	var ui := _ui()
	if ui and ui.has_method("show_ribbon"):
		ui.show_ribbon(meta["stage_label"])
	var tree := get_tree() if is_inside_tree() else null
	var ms: Node = tree.root.get_node_or_null("MatchSelection") if tree else null
	if ms and ResourceLoader.exists(stage_path):
		ms.stage_data = load(stage_path)
	# Delay navigation so the ribbon plays (~1.55s), then hand off to the existing flow.
	if not Engine.is_editor_hint() and tree and tree.current_scene != null:
		var next_scene := "res://scenes/loading_screen.tscn"
		if ms and ms.training:
			next_scene = "res://scenes/training.tscn"
		await tree.create_timer(1.55).timeout
		if is_inside_tree() and tree.current_scene != null:
			tree.change_scene_to_file(next_scene)
```

> The old `label_path` / `_set_label` are gone (the header label is now part of `map_ui`). The scene's `label_path` property from the old bake is harmless but will be removed when Task 9 re-bakes the scene.

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_manager.gd`
Expected: PASS — `NN checks, 0 failures`. (In `--script` tests `confirm()` returns before the timer/navigation because `tree.current_scene` is null, so the emit + ribbon happen synchronously and no scene change occurs — exactly what the asserts check.)

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_manager.gd tests/test_map_manager.gd
git commit -m "feat(map): hover/select/confirm state machine + UI/marker hooks [7.6]"
```

---

### Task 7: Overlay UI — hand-drawn skewed panels (`map_ui.gd`)

Build the full overlay in a single `_draw` Control: header, info panel (skew −2°), stage preview (skew −2°), notched confirm button (skew −3°), and the STAGE LOCKED ribbon (skew −5°). Driven by `set_state` / `show_ribbon`; emits `confirm_pressed` from a small hit Control.

**Files:**
- Create: `scenes/ui/map_select/map_ui.gd`
- Create: `tests/test_map_ui.gd`

**Interfaces:**
- Consumes: fonts from Task 2.
- Produces: `map_ui.gd` extends `CanvasLayer`. `signal confirm_pressed`. Methods: `set_state(d: Dictionary)` (keys per Task 6 `_push_ui`), `show_ribbon(stage_label: String)`, `confirm_rect_contains(p: Vector2) -> bool`. On `_ready` it builds a full-rect `Overlay` Control (draws everything) + a `ConfirmHit` Control (STOP filter) over the button; clicking `ConfirmHit` while `_confirm_enabled` emits `confirm_pressed`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_ui.gd`:

```gdscript
extends SceneTree

const UI := preload("res://scenes/ui/map_select/map_ui.gd")

var checks := 0
var failures := 0
var confirmed := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var ui: CanvasLayer = UI.new()
	get_root().add_child(ui)

	# standby state
	ui.set_state({"kicker": "STANDBY", "accent": Color("#4a5058"),
		"region_name": "SELECT YOUR ARENA", "region_no": "", "fighter": "—",
		"stage": "—", "story": "Hover a region…", "fighter_label": "[Selected Fighter Name]",
		"confirm_enabled": false})
	ok(ui.confirm_rect_contains(Vector2(-999, -999)) == false, "point far outside not in confirm rect")

	# confirm disabled -> click emits nothing
	ui.confirm_pressed.connect(func(): confirmed += 1)
	ui._on_confirm_click()
	ok(confirmed == 0, "disabled confirm ignores click")

	# selected state enables confirm
	ui.set_state({"kicker": "LOCKED IN", "accent": Color("#b154ff"),
		"region_name": "VISAYAS", "region_no": "(REGION 4)", "fighter": "SIKARAN",
		"stage": "HERITAGE PLAZA", "story": "Sikaran…", "fighter_label": "SIKARAN",
		"confirm_enabled": true})
	ui._on_confirm_click()
	ok(confirmed == 1, "enabled confirm emits confirm_pressed")

	# ribbon
	ui.show_ribbon("HERITAGE PLAZA")
	ok(ui.is_ribbon_visible(), "ribbon visible after show_ribbon")

	# a point inside the confirm button rect is detected
	ok(ui.confirm_rect_contains(ui.confirm_rect_centre()), "confirm centre is inside confirm rect")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_ui.gd`
Expected: FAIL — `map_ui.gd` does not exist.

- [ ] **Step 3: Write `map_ui.gd`**

Create `scenes/ui/map_select/map_ui.gd`:

```gdscript
extends CanvasLayer
## Hand-drawn hi-fi overlay for Map Select. One full-rect Control renders every
## panel in a single _draw (skew via draw_set_transform_matrix, notches via
## draw_colored_polygon). A small ConfirmHit Control captures button clicks.

signal confirm_pressed

const DISPLAY_FONT := "res://art/fonts/Anton-Regular.ttf"
const BODY_FONT := "res://art/fonts/Oswald-VariableFont_wght.ttf"

# --- layout (1280x720 screen space) ---
const HEADER_H := 84.0
const PANEL := Rect2(884, 100, 360, 232)      # info panel (pre-skew)
const PREVIEW := Rect2(994, 490, 250, 126)    # stage preview (pre-skew)
const CONFIRM := Rect2(944, 626, 300, 60)     # confirm button (pre-skew)
const NOTCH := 16.0

# --- tokens ---
const INK := Color("#0a0904")
const PANEL_TOP := Color("#181b21")
const PANEL_BOT := Color("#0e1116")
const TXT_HI := Color("#eef1f5")
const TXT_MID := Color("#c4ccd4")
const TXT_LO := Color("#7f8a95")
const GOLD := Color("#ffcf3f")
const CONFIRM_ON := Color("#ffcf3f")
const CONFIRM_OFF := Color("#363b33")
const CONFIRM_TXT_ON := Color("#141007")
const CONFIRM_TXT_OFF := Color("#6b7066")
const RIBBON := Color("#b154ff")

var _display: FontFile
var _body: FontFile
var _overlay: Control
var _hit: Control

var _state := {}
var _ribbon_stage := ""
var _ribbon_visible := false

func _ready() -> void:
	_display = load(DISPLAY_FONT)
	_body = load(BODY_FONT)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_hit = Control.new()
	_hit.name = "ConfirmHit"
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.position = CONFIRM.position
	_hit.size = CONFIRM.size
	_hit.gui_input.connect(_on_hit_input)
	add_child(_hit)

func set_state(d: Dictionary) -> void:
	_state = d
	if _overlay:
		_overlay.queue_redraw()

func show_ribbon(stage_label: String) -> void:
	_ribbon_stage = stage_label
	_ribbon_visible = true
	if _overlay:
		_overlay.queue_redraw()
	# auto-dismiss ~1.55s (matches manager navigation delay)
	if is_inside_tree():
		await get_tree().create_timer(1.55).timeout
		_ribbon_visible = false
		if _overlay:
			_overlay.queue_redraw()

func is_ribbon_visible() -> bool:
	return _ribbon_visible

func confirm_rect_contains(p: Vector2) -> bool:
	return CONFIRM.has_point(p)

func confirm_rect_centre() -> Vector2:
	return CONFIRM.position + CONFIRM.size * 0.5

func _on_hit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_confirm_click()

## Exposed for tests + input: emit only when enabled.
func _on_confirm_click() -> void:
	if _state.get("confirm_enabled", false):
		confirm_pressed.emit()

# ---------- drawing ----------

## CSS skewX(deg): x' = x + y*tan(deg). Pivots about `origin`.
static func _skew_x(deg: float, origin: Vector2) -> Transform2D:
	var t := tan(deg_to_rad(deg))
	return Transform2D(Vector2(1.0, 0.0), Vector2(t, 1.0), origin)

func _draw_overlay() -> void:
	if _state.is_empty():
		return
	_draw_header()
	_draw_panel()
	_draw_preview()
	_draw_confirm()
	if _ribbon_visible:
		_draw_ribbon()

func _draw_header() -> void:
	_overlay.draw_rect(Rect2(0, 0, 1280, HEADER_H), Color("#080a0d"))
	var title := "MAP SELECT"
	var tw := _display.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
	var cx := 640.0 - tw.x * 0.5
	_overlay.draw_string(_display, Vector2(cx + 3, 33), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, INK)
	_overlay.draw_string(_display, Vector2(cx, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, TXT_HI)
	var flabel: String = _state.get("fighter_label", "")
	var sub := "FIGHTER:  "
	var sw := _body.get_string_size(sub + flabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var sx := 640.0 - sw.x * 0.5
	_overlay.draw_string(_body, Vector2(sx, 58), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#cdd5dc"))
	var lead := _body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_overlay.draw_string(_body, Vector2(sx + lead, 58), flabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)

func _draw_panel() -> void:
	var xf := _skew_x(-2.0, PANEL.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := PANEL
	# hard shadow
	_overlay.draw_rect(Rect2(r.position + Vector2(11, 13), r.size), Color(0, 0, 0, 0.9))
	# border + gradient body (two-band approximation of the vertical gradient)
	_overlay.draw_rect(r, INK)
	var inner := r.grow(-5.0)
	_overlay.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.5)), PANEL_TOP)
	_overlay.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.5),
		Vector2(inner.size.x, inner.size.y * 0.5)), PANEL_BOT)
	# accent strip
	var accent: Color = _state.get("accent", Color("#4a5058"))
	_overlay.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 6)), accent)
	# text
	var x := inner.position.x + 17
	var y := inner.position.y + 26
	_overlay.draw_string(_body, Vector2(x, y), _state.get("kicker", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
	y += 30
	_overlay.draw_string(_display, Vector2(x, y), _state.get("region_name", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#f2f4f7"))
	var nmw := _display.get_string_size(_state.get("region_name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_overlay.draw_string(_body, Vector2(x + nmw + 8, y), _state.get("region_no", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8b94a0"))
	y += 20
	# dashed divider
	var dx := x
	while dx < inner.position.x + inner.size.x - 17:
		_overlay.draw_rect(Rect2(dx, y, 10, 2), Color("#3a4049"))
		dx += 16
	y += 22
	_draw_kv(x, y, "FIGHTER", _state.get("fighter", ""), GOLD); y += 24
	_draw_kv(x, y, "STAGE", _state.get("stage", ""), Color("#e7edf2")); y += 24
	_draw_kv(x, y, "CONTEXT", "", TXT_MID)
	_overlay.draw_multiline_string(_body, Vector2(x + 78, y), _state.get("story", ""),
		HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 95, 13, 3, Color("#aab3bc"))
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_kv(x: float, y: float, key: String, val: String, val_col: Color) -> void:
	_overlay.draw_string(_body, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TXT_LO)
	if val != "":
		_overlay.draw_string(_body, Vector2(x + 78, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, val_col)

func _draw_preview() -> void:
	var xf := _skew_x(-2.0, PREVIEW.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := PREVIEW
	_overlay.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.9))
	_overlay.draw_rect(r, INK)
	var inner := r.grow(-5.0)
	_overlay.draw_rect(inner, Color("#161920"))
	# diagonal stripes
	var accent: Color = _state.get("accent", Color("#4a5058"))
	var stage: String = _state.get("stage", "—")
	_overlay.draw_string(_body, inner.position + Vector2(14, 22), "STAGE PREVIEW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#6f7883"))
	_overlay.draw_string(_display, inner.position + Vector2(14, 52), stage,
		HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 24, 18, Color("#e7edf2"))
	_overlay.draw_string(_body, inner.position + Vector2(14, inner.size.y - 12),
		"[ drop stage art · 16:9 ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#5c646d"))
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_confirm() -> void:
	var enabled: bool = _state.get("confirm_enabled", false)
	var xf := _skew_x(-3.0, CONFIRM.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := CONFIRM
	_overlay.draw_polygon(_notched(Rect2(r.position + Vector2(8, 11), r.size)),
		PackedColorArray([Color(0, 0, 0, 1)]))
	_overlay.draw_polygon(_notched(r), PackedColorArray([INK]))
	_overlay.draw_polygon(_notched(r.grow(-5.0)),
		PackedColorArray([CONFIRM_ON if enabled else CONFIRM_OFF]))
	var label := "CONFIRM SELECTION"
	var lw := _display.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_overlay.draw_string(_display, r.position + Vector2((r.size.x - lw) * 0.5, 40), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CONFIRM_TXT_ON if enabled else CONFIRM_TXT_OFF)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

## Rectangle with the top-left + bottom-right corners notched (clip-path style).
static func _notched(r: Rect2) -> PackedVector2Array:
	var p := r.position
	var s := r.size
	return PackedVector2Array([
		p + Vector2(NOTCH, 0), p + Vector2(s.x, 0),
		p + Vector2(s.x, s.y - NOTCH), p + Vector2(s.x - NOTCH, s.y),
		p + Vector2(0, s.y), p + Vector2(0, NOTCH)])

func _draw_ribbon() -> void:
	var centre := Vector2(640, 360)
	var size := Vector2(520, 108)
	var r := Rect2(centre - size * 0.5, size)
	var xf := _skew_x(-5.0, centre)
	_overlay.draw_set_transform_matrix(xf)
	_overlay.draw_rect(Rect2(r.position + Vector2(12, 14), r.size), Color(0, 0, 0, 1))
	_overlay.draw_rect(r, INK)
	_overlay.draw_rect(r.grow(-6.0), RIBBON)
	var kicker := "STAGE LOCKED"
	var kw := _body.get_string_size(kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_overlay.draw_string(_body, Vector2(centre.x - kw * 0.5, r.position.y + 36), kicker,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1a0d29"))
	var sw := _display.get_string_size(_ribbon_stage, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_overlay.draw_string(_display, Vector2(centre.x - sw * 0.5, r.position.y + 82), _ribbon_stage,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_ui.gd`
Expected: PASS — `N checks, 0 failures`, no errors. (Headless has no real draw surface, but `queue_redraw` + `_draw` run without a window; if a font glyph-render warning appears it is non-fatal. The test asserts state/signals, not pixels.)

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_ui.gd tests/test_map_ui.gd
git commit -m "feat(map): hand-drawn skewed overlay UI (panel/preview/confirm/ribbon) [7.6]"
```

---

### Task 8: Markers — upright beacons + light beams (`map_markers.gd`)

Draw a pulsing beacon + upright 3-cone light beam at each region's projected centroid, in flat screen space (z 30) so beams stand upright for free. Expose per-region color updates for hover/select.

**Files:**
- Create: `scenes/ui/map_select/map_markers.gd`
- Create: `tests/test_map_markers.gd`

**Interfaces:**
- Consumes: region centroid metadata (Task 3) + `MapPlane` transform (Task 4) at runtime; or explicit entries in tests.
- Produces: `map_markers.gd` extends `Node2D`. Methods: `build(entries: Array)` where each entry is `{"gid": String, "pos": Vector2, "color": Color}` (screen-space `pos`); `set_color(gid: String, color: Color)`; `_ready` auto-builds from `map_plane_path` + region centroids when set. Each beacon is a child `Node2D` named by `gid` that draws its halo/core/beam and pulses via a looping tween.

- [ ] **Step 1: Write the failing test**

Create `tests/test_map_markers.gd`:

```gdscript
extends SceneTree

const Markers := preload("res://scenes/ui/map_select/map_markers.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var m: Node2D = Markers.new()
	get_root().add_child(m)
	m.build([
		{"gid": "Visayas", "pos": Vector2(600, 300), "color": Color("#6b4a9c")},
		{"gid": "Mindanao", "pos": Vector2(650, 500), "color": Color("#c0982f")},
	])
	ok(m.get_node_or_null("Visayas") != null, "beacon node created for Visayas")
	ok(m.get_node_or_null("Mindanao") != null, "beacon node created for Mindanao")
	var vis: Node2D = m.get_node("Visayas")
	ok(vis.position == Vector2(600, 300), "beacon positioned at screen centroid")

	m.set_color("Visayas", Color("#b154ff"))
	ok(m.marker_color("Visayas") == Color("#b154ff"), "set_color updates stored color")
	ok(m.marker_color("Mindanao") == Color("#c0982f"), "other marker unchanged")

	# rebuild replaces cleanly (idempotent)
	m.build([{"gid": "Visayas", "pos": Vector2(10, 10), "color": Color.WHITE}])
	var count := 0
	for c in m.get_children():
		count += 1
	ok(count == 1, "rebuild frees old beacons (got %d)" % count)

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_markers.gd`
Expected: FAIL — `map_markers.gd` does not exist.

- [ ] **Step 3: Write `map_markers.gd`**

Create `scenes/ui/map_select/map_markers.gd`:

```gdscript
extends Node2D
## Upright beacons + light beams at each region's projected centroid. Lives in flat
## screen space (z 30) between the tilted map and the overlay UI, so the beams stand
## upright with no counter-rotation. Colors track hover/select via set_color.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")
const INK := Color("#0a0904")

@export var map_plane_path: NodePath

var _colors := {}   # gid -> Color

func _ready() -> void:
	z_index = 30
	if get_child_count() == 0 and not map_plane_path.is_empty():
		_auto_build()

## Build from region centroids projected through the MapPlane transform.
func _auto_build() -> void:
	var plane := get_node_or_null(map_plane_path) as Node2D
	if plane == null:
		return
	var entries := []
	for gid in Data.REGION_ORDER:
		var region := plane.get_node_or_null(NodePath(gid)) as Node2D
		if region == null or not region.has_meta("centroid"):
			continue
		var centroid: Vector2 = region.get_meta("centroid")
		entries.append({"gid": gid, "pos": plane.transform * centroid,
			"color": Data.REGIONS[gid]["base"]})
	build(entries)

func build(entries: Array) -> void:
	for c in get_children():
		c.free()
	_colors.clear()
	for e in entries:
		var gid: String = e["gid"]
		_colors[gid] = e["color"]
		var beacon := Node2D.new()
		beacon.name = gid
		beacon.position = e["pos"]
		add_child(beacon)
		beacon.set_meta("gid", gid)
		beacon.draw.connect(_draw_beacon.bind(beacon))
		_pulse(beacon)

func set_color(gid: String, color: Color) -> void:
	if not _colors.has(gid):
		return
	_colors[gid] = color
	var beacon := get_node_or_null(NodePath(gid))
	if beacon:
		beacon.queue_redraw()

func marker_color(gid: String) -> Color:
	return _colors.get(gid, Color.WHITE)

## Gentle infinite pulse on the beacon's scale (beamPulse/corePulse feel).
func _pulse(beacon: Node2D) -> void:
	if not is_inside_tree():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(beacon, "scale", Vector2(1.12, 1.12), 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(beacon, "scale", Vector2(1.0, 1.0), 1.1).set_trans(Tween.TRANS_SINE)

func _draw_beacon(beacon: Node2D) -> void:
	var col: Color = _colors.get(String(beacon.name), Color.WHITE)
	# upright light beam: a soft vertical cone rising from the beacon
	var beam := PackedVector2Array([
		Vector2(-4, 0), Vector2(4, 0), Vector2(26, -190), Vector2(-26, -190)])
	beacon.draw_colored_polygon(beam, Color(col.r, col.g, col.b, 0.22))
	var core_beam := PackedVector2Array([
		Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(7, -180), Vector2(-7, -180)])
	beacon.draw_colored_polygon(core_beam, Color(col.r, col.g, col.b, 0.5))
	# pulsing halo
	beacon.draw_circle(Vector2.ZERO, 22.0, Color(col.r, col.g, col.b, 0.25))
	# core dot with ink ring
	beacon.draw_circle(Vector2.ZERO, 9.5, INK)
	beacon.draw_circle(Vector2.ZERO, 7.0, col)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_markers.gd`
Expected: PASS — `N checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scenes/ui/map_select/map_markers.gd tests/test_map_markers.gd
git commit -m "feat(map): upright beacon + light-beam markers layer [7.6]"
```

---

### Task 9: Assemble the scene + integration boot test

Rewrite the headless builder to compose the full layered scene (background → tilted MapPlane → markers → UI), wire the manager's node paths, re-bake `MapSelection.tscn`, and add an end-to-end boot test.

**Files:**
- Modify: `scripts/dev/build_map_scene.gd` (full rewrite of `_init`)
- Modify: `tests/test_map_select_scene.gd` (integration expectations for the new tree)
- Regenerated: `scenes/ui/map_select/MapSelection.tscn`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: `res://scenes/ui/map_select/MapSelection.tscn` with tree: `MapRoot (map_manager.gd)` → `Background (ColorRect + background.gdshader, z-10)`, `MapPlane (Node2D, tilt transform)` → 5 region nodes, `Markers (map_markers.gd, map_plane_path set)`, `UI (map_ui.gd)`. `MapRoot` has `map_plane_path`, `ui_path`, `markers_path` set.

- [ ] **Step 1: Rewrite `build_map_scene.gd`**

Replace the entire body of `scripts/dev/build_map_scene.gd` with:

```gdscript
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
```

- [ ] **Step 2: Re-bake the scene**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://scripts/dev/build_map_scene.gd`
Expected: `SUCCESS: saved res://scenes/ui/map_select/MapSelection.tscn`, exit 0. `git status` shows `MapSelection.tscn` modified.

- [ ] **Step 3: Write the integration test — rewrite `tests/test_map_select_scene.gd`**

Replace its contents with:

```gdscript
extends SceneTree
## End-to-end: MapSelection.tscn boots with all layers, hit-tests through the tilt,
## selects + gates confirm, all headless with no script/parse/decompose errors.

const SCENE := "res://scenes/ui/map_select/MapSelection.tscn"
const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	var packed: PackedScene = load(SCENE)
	ok(packed != null, "MapSelection.tscn loads")
	if packed == null:
		_finish(); return
	var scene: Node = packed.instantiate()
	get_root().add_child(scene)
	await process_frame   # let children build (markers auto-build, UI _ready)
	await process_frame

	ok(scene.get_node_or_null("Background") != null, "Background layer present")
	ok(scene.get_node_or_null("MapPlane") != null, "MapPlane present")
	ok(scene.get_node_or_null("Markers") != null, "Markers present")
	ok(scene.get_node_or_null("UI") != null, "UI present")

	var plane: Node2D = scene.get_node("MapPlane")
	var regions := 0
	for gid in Data.REGION_ORDER:
		if plane.get_node_or_null(NodePath(gid)) != null:
			regions += 1
	ok(regions == 5, "5 regions under MapPlane (got %d)" % regions)

	# markers auto-built one beacon per region
	var markers: Node2D = scene.get_node("Markers")
	ok(markers.get_child_count() == 5, "5 beacons built (got %d)" % markers.get_child_count())

	# hit-test an interior point through the tilt
	var vis: Node2D = plane.get_node("Visayas")
	var top: Node2D = vis.get_node("Visual/Top")
	var poly: Polygon2D = null
	for c in top.get_children():
		if c is Polygon2D:
			poly = c; break
	ok(poly != null, "Visayas has a Top polygon")
	if poly:
		var inside := _interior(poly.polygon)
		ok(inside != Vector2.INF, "found interior point")
		if inside != Vector2.INF:
			var hit: Node2D = scene._region_at(plane.to_global(inside))
			ok(hit == vis, "_region_at resolves Visayas through tilt")
			# select + confirm gating
			scene._select(vis)
			ok(scene._selected == vis, "click selects Visayas")

	_finish()

func _interior(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts: c += p
	c /= pts.size()
	if Geometry2D.is_point_in_polygon(c, pts):
		return c
	var lo := pts[0]; var hi := pts[0]
	for p in pts:
		lo = lo.min(p); hi = hi.max(p)
	for i in range(1, 24):
		for j in range(1, 24):
			var s := Vector2(lerpf(lo.x, hi.x, i / 24.0), lerpf(lo.y, hi.y, j / 24.0))
			if Geometry2D.is_point_in_polygon(s, pts):
				return s
	return Vector2.INF

func _finish() -> void:
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 4: Run the integration test**

Run: `/home/jacob/Godot_v4.7-stable_linux.x86_64 --headless --path /home/jacob/LOTA --script res://tests/test_map_select_scene.gd`
Expected: PASS — `NN checks, 0 failures`, exit 0, and NO `SCRIPT ERROR` / `SHADER ERROR` / decompose lines in stderr.

- [ ] **Step 5: Run the full map test suite**

```bash
B=/home/jacob/Godot_v4.7-stable_linux.x86_64
for t in test_map_data test_map_generator test_map_baker test_map_manager test_map_ui test_map_markers test_background_shader test_map_select_scene; do
  echo "== $t =="
  $B --headless --path /home/jacob/LOTA --script res://tests/$t.gd || echo "FAILED: $t"
done
```
Expected: every test prints `… 0 failures` and none print `FAILED:`.

- [ ] **Step 6: Boot the scene live (visual smoke)**

Run: `timeout 8 /home/jacob/Godot_v4.7-stable_linux.x86_64 --path /home/jacob/LOTA res://scenes/ui/map_select/MapSelection.tscn`
Expected: window opens showing the tilted map + background + UI; terminates on timeout ("Terminated") with no `SCRIPT ERROR` / `SHADER ERROR` lines. (If headless-only environment, skip and rely on Step 4–5.)

- [ ] **Step 7: Commit**

```bash
git add scripts/dev/build_map_scene.gd tests/test_map_select_scene.gd \
        scenes/ui/map_select/MapSelection.tscn
git commit -m "feat(map): assemble hi-fi map-select scene (bg/tilt/markers/UI) + integration test [7.6]"
```

---

## Self-Review

**Spec coverage** (against `2026-07-05-map-select-hifi-design.md`):
- Layer 1 Background dusk-ocean → Task 5 (shader) + Task 9 (ColorRect z−10). ✓
- Layer 2 MapPlane affine tilt (−20°, cos 49°) → Task 4 (`tilt_transform`) + Task 9 (applied). ✓
- Layer 3 Regions: extruded underside + top face + hard shadow, per-region color, plane-local hit-testing → Task 3 (bake) + Task 4/6 (hit-test on `Visual/Top`). ✓
- Layer 4 Markers (beacons + upright beams) → Task 8; Header/Info panel/Stage preview/Confirm/Ribbon → Task 7. ✓
- Region metadata single source of truth + corrected stage mapping → Task 1. ✓
- Interactions (hover gold, select neon, hover priority, confirm→ribbon→navigate, training route) → Task 6. ✓
- Fonts Anton + Oswald → Task 2, consumed in Task 7. ✓
- Testing (data, bake, hit-test, state, boot) → Tasks 1,3,4,6,7,8,9 tests. ✓
- Performance (static tilt, interaction-only tweens, reused simplified rings) → preserved; generator still Douglas-Peucker simplifies. ✓

**Type consistency:** bake layer names `Shadow`/`Underside`/`Top` are identical in Task 3 (writer), Task 4/6 (`Visual/Top` reader), and Task 9 test. `set_state`/`show_ribbon`/`confirm_pressed`/`set_color`/`marker_color`/`build` signatures match between producer (Tasks 7,8) and consumer (Task 6) and tests. `tilt_transform`, `TILT_ROT_DEG`, `TILT_SCALE_Y`, `REGION_ORDER`, `INK`, `UNDERSIDE` are defined in Task 1/4 and referenced consistently downstream. `region_selected` now emits `display` (UPPERCASE) — Task 6 test asserts `"VISAYAS"` accordingly (behavior change from the old title-case, intentional).

**Placeholder scan:** no TBD/TODO; every code step has full code; commands have expected output. The only intentional fallback is Task 2 Step 2 (font download blocked → BebasNeue), which is a concrete, guarded contingency, not a placeholder.

**Known deviation (flagged):** the info-panel vertical gradient is approximated as two solid bands (`PANEL_TOP`/`PANEL_BOT`) since `_draw` has no cheap vertical gradient; the diagonal-stripe preview background is simplified to a solid `#161920`. Both are cosmetic and can be upgraded later without interface changes.
