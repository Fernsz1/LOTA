# Map Select / Stage Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An interactive Map Select screen where the player picks a stage by clicking one of 5 regions on an accurate map of the Philippines, replacing the old grid `stage_select` in the live match flow.

**Architecture:** An offline Python script bakes real Philippines GeoJSON (grouped into 5 game regions, internal borders dissolved, equirectangular-projected) into `data/map_regions.json`. At runtime `map_select.gd` loads that JSON and builds one interactive node per region (Polygon2D fill + Line2D outline + Area2D hit-test) inside a graphic-novel-styled Control screen. Confirming a region sets `MatchSelection.stage_data` and advances to the loading screen.

**Tech Stack:** Godot 4.7 / GDScript, Python 3 (stdlib only) for the bake, existing `UIPalette`, `art/fonts/BebasNeue-Regular.ttf` + `Bangers-Regular.ttf`, `assets/hud/halftone_tile.png`.

## Global Constraints

- Target resolution **1280×720** (project.godot; `canvas_items` stretch, `expand` aspect). Design at native 1280×720.
- GDScript style per `docs/conventions.md`: tabs, static typing where cheap, `snake_case` files, `PascalCase` `class_name`, `snake_case()` methods, past-tense signals.
- This screen is UI/rendering only — `_process`/`delta`/`Tween` are permitted here (no combat determinism).
- Tests are plain `extends SceneTree` scripts using a manual `_check(cond, msg)` harness and `quit(1 if _failures > 0 else 0)`. Run headless: `godot --headless --path . --script res://tests/<file>.gd`. **Not** GUT. Use untyped `var x: Resource = load(...)` in tests (global `class_name` symbols aren't registered in isolated `--script` mode).
- Godot binary + headless test invocation per the `lota-godot-binary` memory.
- User owns commits (no Claude co-author trailer). Commit steps below are for the implementer to run; conventional-commit messages given.
- Branch: `feat/7.6-map-select` off `dev` (phase number provisional — confirm against current plan phase before branching).

**Region reference table** (used across tasks — id = region_number):

| id | display_name | GeoJSON codes (filenames `provdists-region-<code>.0.001.json`) | stage_name | fighter_name | accent |
|---|---|---|---|---|---|
| 1 | Luzon | 400000000, 1700000000, 500000000 | Bahay Kubo Training Yard | Arnis Fighter | `#f5b431` |
| 2 | Northern Luzon | 100000000, 200000000, 1400000000 | Mountain Festival Grounds | Buno Fighter | `#22d3ee` |
| 3 | Metro Manila | 300000000, 1300000000 | Barangay Boxing Ring | Dirty Boxing Fighter | `#ef4444` |
| 4 | Visayas | 600000000, 700000000, 800000000 | Heritage Plaza | Sikaran Fighter | `#b366ff` |
| 5 | Mindanao | 900000000, 1000000000, 1100000000, 1200000000, 1600000000, 1900000000 | Beach Court at Dusk | Sepak Takraw Striker | `#fb7a2d` |

Story context (baked verbatim):
- 1 Luzon: `In a quiet village in Luzon, warriors train in secret, preserving the way of the rattan.`
- 2 Northern Luzon: `In the highlands, strength is tested in fair combat. Buno is respect, balance, and honor.`
- 3 Metro Manila: `From makeshift rings in the barangays rise champions. Grit, heart, and never giving up.`
- 4 Visayas: `Sikaran was born from freedom and resilience. Warriors honed their kicks to protect their people.`
- 5 Mindanao: `On coastal shores, every kick honors the players who made the Philippines a Sepak Takraw powerhouse.`

stage_data_path per id → `res://stages/<slug>/<slug>_data.tres` with slugs: 1 `bahay_kubo`, 2 `mountain_festival`, 3 `barangay_ring`, 4 `heritage_plaza`, 5 `beach_court`.

---

## Task 1: Vendor GeoJSON + bake pipeline → `data/map_regions.json`

**Files:**
- Create: `data/geojson_src/provdists-region-<code>.0.001.json` (17 files, fetched)
- Create: `scripts/dev/bake_map_regions.py`
- Create: `data/map_regions.json` (bake output)

**Interfaces:**
- Produces: `data/map_regions.json` with shape `{ "map_size": [w, h], "regions": [ { "id": int, "display_name": str, "region_number": int, "stage_name": str, "fighter_name": str, "story_context": str, "accent_color": "#rrggbb", "stage_data_path": "res://…", "label_anchor": [x, y], "outline_polygons": [[x0,y0,x1,y1,…], …] } × 5 ] }`. Coordinates are floats in a top-left-origin pixel space sized `map_size` (height fit to 560px).

- [ ] **Step 1: Fetch the 17 source GeoJSON files**

```bash
cd /home/jacob/LOTA
mkdir -p data/geojson_src
BASE="https://raw.githubusercontent.com/faeldon/philippines-json-maps/master/2023/geojson/regions/lowres"
for c in 100000000 200000000 300000000 400000000 500000000 600000000 700000000 800000000 900000000 1000000000 1100000000 1200000000 1300000000 1400000000 1600000000 1700000000 1900000000; do
  curl -sf "$BASE/provdists-region-$c.0.001.json" -o "data/geojson_src/provdists-region-$c.0.001.json" && echo "ok $c" || echo "FAIL $c"
done
ls data/geojson_src | wc -l   # expect 17
```
Expected: 17 `ok` lines; file count 17. If any `FAIL`, re-run (transient) — do not proceed until all 17 exist and are non-empty.

- [ ] **Step 2: Write the bake script**

Create `scripts/dev/bake_map_regions.py`:

```python
#!/usr/bin/env python3
"""Bake Philippines region GeoJSON into data/map_regions.json for LOTA map select.

Groups 17 PSGC admin regions into 5 game regions, dissolves internal province
borders (directed-edge cancellation), drops speck islands, and equirectangular-
projects into a top-left-origin pixel space (height fit to TARGET_H). Runtime
loads the baked JSON only; it never parses GeoJSON.

Run: python3 scripts/dev/bake_map_regions.py
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "data", "geojson_src")
OUT = os.path.join(ROOT, "data", "map_regions.json")

TARGET_H = 560.0        # projected map height in px; width follows aspect
MIN_AREA_PX = 8.0       # drop rings whose projected area is below this (specks)
RND = 6                 # coordinate rounding (decimal places) for edge matching

# game region -> metadata + source file codes
GROUPS = [
    {"id": 1, "name": "Luzon", "codes": ["400000000", "1700000000", "500000000"],
     "stage": "Bahay Kubo Training Yard", "fighter": "Arnis Fighter", "accent": "#f5b431",
     "slug": "bahay_kubo",
     "ctx": "In a quiet village in Luzon, warriors train in secret, preserving the way of the rattan."},
    {"id": 2, "name": "Northern Luzon", "codes": ["100000000", "200000000", "1400000000"],
     "stage": "Mountain Festival Grounds", "fighter": "Buno Fighter", "accent": "#22d3ee",
     "slug": "mountain_festival",
     "ctx": "In the highlands, strength is tested in fair combat. Buno is respect, balance, and honor."},
    {"id": 3, "name": "Metro Manila", "codes": ["300000000", "1300000000"],
     "stage": "Barangay Boxing Ring", "fighter": "Dirty Boxing Fighter", "accent": "#ef4444",
     "slug": "barangay_ring",
     "ctx": "From makeshift rings in the barangays rise champions. Grit, heart, and never giving up."},
    {"id": 4, "name": "Visayas", "codes": ["600000000", "700000000", "800000000"],
     "stage": "Heritage Plaza", "fighter": "Sikaran Fighter", "accent": "#b366ff",
     "slug": "heritage_plaza",
     "ctx": "Sikaran was born from freedom and resilience. Warriors honed their kicks to protect their people."},
    {"id": 5, "name": "Mindanao",
     "codes": ["900000000", "1000000000", "1100000000", "1200000000", "1600000000", "1900000000"],
     "stage": "Beach Court at Dusk", "fighter": "Sepak Takraw Striker", "accent": "#fb7a2d",
     "slug": "beach_court",
     "ctx": "On coastal shores, every kick honors the players who made the Philippines a Sepak Takraw powerhouse."},
]


def _rings_from_geometry(geom):
    """Yield every linear ring (list of [lon,lat]) from a Polygon/MultiPolygon."""
    t = geom["type"]
    if t == "Polygon":
        for ring in geom["coordinates"]:
            yield ring
    elif t == "MultiPolygon":
        for poly in geom["coordinates"]:
            for ring in poly:
                yield ring


def _load_group_rings(codes):
    rings = []
    for code in codes:
        path = os.path.join(SRC, "provdists-region-%s.0.001.json" % code)
        with open(path) as f:
            gj = json.load(f)
        for feat in gj["features"]:
            geom = feat.get("geometry")
            if geom:
                rings.extend(_rings_from_geometry(geom))
    return rings


def _key(pt):
    return (round(pt[0], RND), round(pt[1], RND))


def _dissolve(rings):
    """Directed-edge cancellation -> list of boundary rings (lon/lat)."""
    edges = set()          # (keyA, keyB)
    coord = {}             # key -> original [lon,lat]
    for ring in rings:
        for i in range(len(ring) - 1):
            a, b = ring[i], ring[i + 1]
            ka, kb = _key(a), _key(b)
            if ka == kb:
                continue
            coord[ka], coord[kb] = a, b
            edges.add((ka, kb))
    # cancel any edge whose reverse also exists (shared internal border)
    survivors = {(a, b) for (a, b) in edges if (b, a) not in edges}
    # stitch survivors into closed rings
    adj = {}
    for (a, b) in survivors:
        adj.setdefault(a, []).append(b)
    out_rings = []
    remaining = set(survivors)
    while remaining:
        start, nxt = next(iter(remaining))
        ring = [coord[start]]
        cur, prev_edge = nxt, (start, nxt)
        remaining.discard(prev_edge)
        guard = 0
        while cur != start and guard < 100000:
            ring.append(coord[cur])
            outs = [b for b in adj.get(cur, []) if (cur, b) in remaining]
            if not outs:
                break
            nb = outs[0]
            remaining.discard((cur, nb))
            cur = nb
            guard += 1
        ring.append(coord[start])
        out_rings.append(ring)
    return out_rings


def _shoelace(ring):
    s = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def _centroid(ring):
    a = _shoelace(ring)
    if abs(a) < 1e-12:
        xs = [p[0] for p in ring]
        ys = [p[1] for p in ring]
        return [sum(xs) / len(xs), sum(ys) / len(ys)]
    cx = cy = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i]
        x1, y1 = ring[i + 1]
        cross = x0 * y1 - x1 * y0
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    cx /= (6 * a)
    cy /= (6 * a)
    return [cx, cy]


def main():
    groups_rings = {}
    for g in GROUPS:
        groups_rings[g["id"]] = _dissolve(_load_group_rings(g["codes"]))

    # global bbox for the shared projection
    all_pts = [pt for rings in groups_rings.values() for r in rings for pt in r]
    lon_min = min(p[0] for p in all_pts)
    lon_max = max(p[0] for p in all_pts)
    lat_min = min(p[1] for p in all_pts)
    lat_max = max(p[1] for p in all_pts)
    mid_lat = math.radians((lat_min + lat_max) / 2.0)
    raw_w = (lon_max - lon_min) * math.cos(mid_lat)
    raw_h = (lat_max - lat_min)
    k = TARGET_H / raw_h
    map_w = raw_w * k
    map_h = raw_h * k

    def project(pt):
        x = (pt[0] - lon_min) * math.cos(mid_lat) * k
        y = (lat_max - pt[1]) * k
        return (x, y)

    regions = []
    for g in GROUPS:
        proj_rings = []
        for r in groups_rings[g["id"]]:
            pr = [project(pt) for pt in r]
            if abs(_shoelace(pr)) < MIN_AREA_PX:
                continue          # speck island
            proj_rings.append(pr)
        proj_rings.sort(key=lambda r: abs(_shoelace(r)), reverse=True)
        anchor = _centroid(proj_rings[0])
        flat = [[c for pt in r for c in (round(pt[0], 2), round(pt[1], 2))] for r in proj_rings]
        regions.append({
            "id": g["id"],
            "display_name": g["name"],
            "region_number": g["id"],
            "stage_name": g["stage"],
            "fighter_name": g["fighter"],
            "story_context": g["ctx"],
            "accent_color": g["accent"],
            "stage_data_path": "res://stages/%s/%s_data.tres" % (g["slug"], g["slug"]),
            "label_anchor": [round(anchor[0], 2), round(anchor[1], 2)],
            "outline_polygons": flat,
        })

    out = {"map_size": [round(map_w, 2), round(map_h, 2)], "regions": regions}
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)

    # self-check
    assert len(regions) == 5, "expected 5 regions"
    for r in regions:
        assert r["outline_polygons"] and all(len(p) >= 6 for p in r["outline_polygons"]), \
            "region %s has an empty ring" % r["id"]
    print("baked %d regions, map_size=%s -> %s" % (len(regions), out["map_size"], OUT))


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the bake**

Run: `cd /home/jacob/LOTA && python3 scripts/dev/bake_map_regions.py`
Expected: `baked 5 regions, map_size=[~321.x, 560.0] -> …/data/map_regions.json` and no `AssertionError`.

- [ ] **Step 4: Sanity-check the output**

Run:
```bash
python3 -c "import json;d=json.load(open('data/map_regions.json'));print(len(d['regions']),[r['display_name'] for r in d['regions']]);print([len(r['outline_polygons']) for r in d['regions']])"
```
Expected: `5 ['Luzon', 'Northern Luzon', 'Metro Manila', 'Visayas', 'Mindanao']` and each ring-count ≥ 1. If Mindanao/Visayas show only 1 ring, that's fine (largest island survived); if any region shows 0 rings, lower `MIN_AREA_PX` and re-run.

- [ ] **Step 5: Commit**

```bash
git add scripts/dev/bake_map_regions.py data/geojson_src data/map_regions.json
git commit -m "chore(map): vendor PH region geojson + bake script"
```

---

## Task 2: Author 5 region StageData resources

**Files:**
- Create: `stages/bahay_kubo/bahay_kubo_data.tres`
- Create: `stages/mountain_festival/mountain_festival_data.tres`
- Create: `stages/barangay_ring/barangay_ring_data.tres`
- Create: `stages/heritage_plaza/heritage_plaza_data.tres`
- Create: `stages/beach_court/beach_court_data.tres`

**Interfaces:**
- Consumes: `scripts/stage/stage_data.gd` (`StageData`: `stage_name`, `background_color`, `floor_color`).
- Produces: 5 loadable `StageData` at the `stage_data_path`s baked in Task 1.

- [ ] **Step 1: Write a failing loader test**

Create `tests/test_region_stages.gd`:
```gdscript
extends SceneTree
## Headless check: the 5 map-region StageData resources load with the right names.

var _checks := 0
var _failures := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var expect := {
		"res://stages/bahay_kubo/bahay_kubo_data.tres": "Bahay Kubo Training Yard",
		"res://stages/mountain_festival/mountain_festival_data.tres": "Mountain Festival Grounds",
		"res://stages/barangay_ring/barangay_ring_data.tres": "Barangay Boxing Ring",
		"res://stages/heritage_plaza/heritage_plaza_data.tres": "Heritage Plaza",
		"res://stages/beach_court/beach_court_data.tres": "Beach Court at Dusk",
	}
	for path: String in expect:
		var sd: Resource = load(path)
		_check(sd != null, "loads %s" % path)
		_check(sd != null and sd.stage_name == expect[path], "stage_name == %s" % expect[path])
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless --path . --script res://tests/test_region_stages.gd`
Expected: FAIL lines ("loads res://stages/bahay_kubo/…" fails — files don't exist yet).

- [ ] **Step 3: Create the 5 resources**

`stages/bahay_kubo/bahay_kubo_data.tres`:
```
[gd_resource type="Resource" script_class="StageData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/stage/stage_data.gd" id="1"]

[resource]
script = ExtResource("1")
stage_name = "Bahay Kubo Training Yard"
background_color = Color(0.35, 0.28, 0.12, 1)
floor_color = Color(0.2, 0.16, 0.08, 1)
```
`stages/mountain_festival/mountain_festival_data.tres`:
```
[gd_resource type="Resource" script_class="StageData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/stage/stage_data.gd" id="1"]

[resource]
script = ExtResource("1")
stage_name = "Mountain Festival Grounds"
background_color = Color(0.12, 0.28, 0.32, 1)
floor_color = Color(0.1, 0.18, 0.2, 1)
```
`stages/barangay_ring/barangay_ring_data.tres`:
```
[gd_resource type="Resource" script_class="StageData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/stage/stage_data.gd" id="1"]

[resource]
script = ExtResource("1")
stage_name = "Barangay Boxing Ring"
background_color = Color(0.3, 0.12, 0.12, 1)
floor_color = Color(0.18, 0.08, 0.08, 1)
```
`stages/heritage_plaza/heritage_plaza_data.tres`:
```
[gd_resource type="Resource" script_class="StageData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/stage/stage_data.gd" id="1"]

[resource]
script = ExtResource("1")
stage_name = "Heritage Plaza"
background_color = Color(0.22, 0.14, 0.3, 1)
floor_color = Color(0.14, 0.1, 0.2, 1)
```
`stages/beach_court/beach_court_data.tres`:
```
[gd_resource type="Resource" script_class="StageData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/stage/stage_data.gd" id="1"]

[resource]
script = ExtResource("1")
stage_name = "Beach Court at Dusk"
background_color = Color(0.35, 0.2, 0.12, 1)
floor_color = Color(0.2, 0.12, 0.08, 1)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . --script res://tests/test_region_stages.gd`
Expected: all PASS, `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add stages/bahay_kubo stages/mountain_festival stages/barangay_ring stages/heritage_plaza stages/beach_court tests/test_region_stages.gd
git commit -m "feat(map): author 5 region StageData resources [7.6]"
```

---

## Task 3: `SkewPanel` reusable graphic-novel panel

**Files:**
- Create: `scripts/ui/skew_panel.gd`

**Interfaces:**
- Produces: `class_name SkewPanel extends Control`. Exports: `skew_px: float`, `fill_color: Color`, `border_color: Color`, `shadow_color: Color`, `shadow_offset: Vector2`, `border_width: float`, `accent_color: Color`, `header_height: float`. Draws a left-leaning parallelogram (top edge shifted right by `skew_px`) with hard offset shadow, fill, thick border, and an optional accent header strip. Text is added by the consumer as child `Control`s.

- [ ] **Step 1: Write the script**

Create `scripts/ui/skew_panel.gd`:
```gdscript
@tool
class_name SkewPanel
extends Control
## Graphic-novel panel: a slightly skewed parallelogram with a hard black offset
## shadow, solid fill, thick border, and an optional accent header strip. Cel-shaded
## look for map-select chrome (header / tooltip / confirm hub). Purely cosmetic;
## place text/controls as children on top.

@export var skew_px: float = 14.0:
	set(v): skew_px = v; queue_redraw()
@export var fill_color: Color = Color("14101d"):
	set(v): fill_color = v; queue_redraw()
@export var border_color: Color = Color.BLACK:
	set(v): border_color = v; queue_redraw()
@export var shadow_color: Color = Color(0, 0, 0, 0.55):
	set(v): shadow_color = v; queue_redraw()
@export var shadow_offset: Vector2 = Vector2(8, 8):
	set(v): shadow_offset = v; queue_redraw()
@export var border_width: float = 4.0:
	set(v): border_width = v; queue_redraw()
@export var accent_color: Color = Color(0, 0, 0, 0):
	set(v): accent_color = v; queue_redraw()
@export var header_height: float = 0.0:
	set(v): header_height = v; queue_redraw()


func _points() -> PackedVector2Array:
	var s := size
	# top edge shifted right by skew_px -> left-leaning parallelogram
	return PackedVector2Array([
		Vector2(skew_px, 0.0),
		Vector2(s.x, 0.0),
		Vector2(s.x - skew_px, s.y),
		Vector2(0.0, s.y),
	])


func _draw() -> void:
	var pts := _points()
	var shadow := PackedVector2Array()
	for p: Vector2 in pts:
		shadow.append(p + shadow_offset)
	draw_colored_polygon(shadow, shadow_color)
	draw_colored_polygon(pts, fill_color)
	if header_height > 0.0 and accent_color.a > 0.0:
		var hy := header_height
		var head := PackedVector2Array([
			pts[0], pts[1],
			Vector2(pts[1].x - skew_px * (hy / size.y), hy),
			Vector2(pts[0].x - skew_px * (hy / size.y), hy),
		])
		draw_colored_polygon(head, accent_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, border_width)
```

- [ ] **Step 2: Verify it parses**

Run: `godot --headless --path . --check-only --script res://scripts/ui/skew_panel.gd`
Expected: no parse errors (exits cleanly). If `--check-only` is unavailable, run `godot --headless --path . --quit` and confirm no error mentioning `skew_panel.gd`.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/skew_panel.gd
git commit -m "feat(map): add SkewPanel cel-shaded panel control [7.6]"
```

---

## Task 4: `MapRegion` interactive region node

**Files:**
- Create: `scripts/ui/map_region.gd`

**Interfaces:**
- Consumes: baked region dict fields from Task 1.
- Produces: `class_name MapRegion extends Node2D`. Public: `region_id: int`, `accent: Color`, `signal region_hovered(id: int)`, `signal region_clicked(id: int)`, `func setup(data: Dictionary) -> void` (builds fills/outlines/collision/label from a region entry), `func set_active(active: bool) -> void` (tween lift + accent/glow), constant `LIFT_PX := 16.0`.

- [ ] **Step 1: Write the script**

Create `scripts/ui/map_region.gd`:
```gdscript
class_name MapRegion
extends Node2D
## One clickable Philippines region on the map-select screen. Built at runtime from
## a baked region dict (data/map_regions.json). Fill = Polygon2D per ring; outline =
## black Line2D; accent glow = wider Line2D shown when active; hit-test = Area2D +
## CollisionPolygon2D per ring. Hover/selected lifts the whole node uniformly.

signal region_hovered(id: int)
signal region_clicked(id: int)

const LIFT_PX := 16.0
const REST_FILL := Color("63552f")
const OUTLINE_W := 4.0
const GLOW_W := 10.0

var region_id: int = 0
var accent: Color = Color.WHITE

var _fills: Array[Polygon2D] = []
var _glows: Array[Line2D] = []
var _base_y: float = 0.0
var _tween: Tween


func setup(data: Dictionary) -> void:
	region_id = int(data["id"])
	accent = Color(str(data["accent_color"]))
	var rings: Array = data["outline_polygons"]
	var bangers := load("res://art/fonts/Bangers-Regular.ttf")

	for ring: Array in rings:
		var pts := _to_points(ring)

		var glow := Line2D.new()
		glow.points = _closed(pts)
		glow.width = GLOW_W
		glow.default_color = accent
		glow.joint_mode = Line2D.LINE_JOINT_ROUND
		glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		glow.end_cap_mode = Line2D.LINE_CAP_ROUND
		glow.visible = false
		glow.z_index = -1
		add_child(glow)
		_glows.append(glow)

		var fill := Polygon2D.new()
		fill.polygon = pts
		fill.color = REST_FILL
		add_child(fill)
		_fills.append(fill)

		var outline := Line2D.new()
		outline.points = _closed(pts)
		outline.width = OUTLINE_W
		outline.default_color = Color.BLACK
		outline.joint_mode = Line2D.LINE_JOINT_ROUND
		outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
		outline.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(outline)

		var area := Area2D.new()
		var cp := CollisionPolygon2D.new()
		cp.polygon = pts
		area.add_child(cp)
		add_child(area)
		area.mouse_entered.connect(func() -> void: region_hovered.emit(region_id))
		area.input_event.connect(_on_area_input)

	var label := Label.new()
	label.text = str(data["display_name"]).to_upper()
	label.add_theme_font_override("font", bangers)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var anchor: Array = data["label_anchor"]
	label.position = Vector2(float(anchor[0]) - 60.0, float(anchor[1]) - 12.0)
	label.custom_minimum_size = Vector2(120, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _to_points(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < flat.size() - 1:
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
		i += 2
	return out


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var c := pts.duplicate()
	if pts.size() > 0:
		c.append(pts[0])
	return c


func _on_area_input(_vp: Node, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		region_clicked.emit(region_id)


func set_active(active: bool) -> void:
	for g: Line2D in _glows:
		g.visible = active
	var target_fill := accent.darkened(0.45) if active else REST_FILL
	for f: Polygon2D in _fills:
		f.color = target_fill
	z_index = 1 if active else 0
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	var target_y := _base_y - LIFT_PX if active else _base_y
	_tween.tween_property(self, "position:y", target_y, 0.15)


func set_base_y(y: float) -> void:
	_base_y = y
	position.y = y
```

- [ ] **Step 2: Verify it parses**

Run: `godot --headless --path . --check-only --script res://scripts/ui/map_region.gd`
Expected: no parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/map_region.gd
git commit -m "feat(map): add MapRegion interactive region node [7.6]"
```

---

## Task 5: `map_select` scene + controller

**Files:**
- Create: `scenes/map_select.tscn`
- Create: `scripts/map_select.gd`

**Interfaces:**
- Consumes: `data/map_regions.json`, `MapRegion` (Task 4), `SkewPanel` (Task 3), `MatchSelection` autoload, `StageData` paths (Task 2).
- Produces: `signal stage_confirmed(region_id: int, stage_name: String, fighter: String)`; public `func select_region(id: int) -> void`; public `func lock_selection() -> void` (sets `MatchSelection.stage_data`, emits `stage_confirmed`; does **not** change scene — the button handler does that after). Default `selected_id := 4` (Visayas).

- [ ] **Step 1: Write the controller**

Create `scripts/map_select.gd`:
```gdscript
extends Control
## Map Select (7.6). Player picks a stage by clicking one of 5 Philippines regions.
## Regions are built at runtime from data/map_regions.json. Confirming sets
## MatchSelection.stage_data and advances to the loading screen. Replaces the old
## grid stage_select in the character-select -> stage -> loading flow.

signal stage_confirmed(region_id: int, stage_name: String, fighter: String)

const DATA_PATH := "res://data/map_regions.json"
const MAP_CENTER := Vector2(470, 392)   # where the map's bbox center sits on screen

@onready var _map_root: Node2D = $MapContainer
@onready var _fighter_label: Label = $Header/FighterValue
@onready var _tt_title: Label = $Tooltip/Title
@onready var _tt_region: Label = $Tooltip/RegionNum
@onready var _tt_stage: Label = $Tooltip/StageValue
@onready var _tt_unlocks: Label = $Tooltip/UnlocksValue
@onready var _tt_story: Label = $Tooltip/StoryValue
@onready var _hub_stage: Label = $ConfirmHub/StageValue
@onready var _confirm_btn: Button = $ConfirmHub/ConfirmButton

var _regions: Dictionary = {}         # id -> region dict
var _nodes: Dictionary = {}           # id -> MapRegion
var _hovered_id: int = 0
var _selected_id: int = 4
var _locked: bool = false


func _ready() -> void:
	get_viewport().physics_object_picking = true
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	var map_size := Vector2(float(doc["map_size"][0]), float(doc["map_size"][1]))
	_map_root.position = MAP_CENTER - map_size * 0.5
	for data: Dictionary in doc["regions"]:
		var id := int(data["id"])
		_regions[id] = data
		var node := MapRegion.new()
		_map_root.add_child(node)
		node.setup(data)
		node.set_base_y(0.0)
		node.region_hovered.connect(_on_region_hovered)
		node.region_clicked.connect(select_region)
		_nodes[id] = node
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	select_region(_selected_id)


func _active_id() -> int:
	return _hovered_id if _hovered_id != 0 else _selected_id


func _on_region_hovered(id: int) -> void:
	if _locked:
		return
	_hovered_id = id
	_refresh()


func select_region(id: int) -> void:
	if _locked:
		return
	_selected_id = id
	_refresh()
	var d: Dictionary = _regions[id]
	_hub_stage.text = str(d["stage_name"])


func _refresh() -> void:
	var active := _active_id()
	for rid: int in _nodes:
		_nodes[rid].set_active(rid == active)
	var d: Dictionary = _regions[active]
	_fighter_label.text = str(d["fighter_name"])
	_tt_title.text = str(d["display_name"]).to_upper()
	_tt_region.text = "REGION %d" % int(d["region_number"])
	_tt_stage.text = str(d["stage_name"])
	_tt_unlocks.text = str(d["fighter_name"])
	_tt_story.text = str(d["story_context"])
	_tt_title.add_theme_color_override("font_color", Color(str(d["accent_color"])))


func lock_selection() -> void:
	var d: Dictionary = _regions[_selected_id]
	MatchSelection.stage_data = load(str(d["stage_data_path"]))
	_locked = true
	stage_confirmed.emit(_selected_id, str(d["stage_name"]), str(d["fighter_name"]))


func _on_confirm_pressed() -> void:
	if _locked:
		return
	var tw := create_tween()
	tw.tween_property(_confirm_btn, "scale", Vector2(0.94, 0.94), 0.06)
	tw.tween_property(_confirm_btn, "scale", Vector2.ONE, 0.06)
	lock_selection()
	_confirm_btn.text = "STAGE LOCKED IN"
	_confirm_btn.add_theme_color_override("font_color", Color.WHITE)
	_confirm_btn.self_modulate = Color("2ecc71")
	await get_tree().create_timer(0.25).timeout
	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
```

- [ ] **Step 2: Build the scene**

Create `scenes/map_select.tscn` with this tree (author in the editor or write the `.tscn` directly). Root `Control` uses `theme = res://art/ui/lota_theme.tres`, anchors full-rect (`anchor_right=1`, `anchor_bottom=1`), `script = res://scripts/map_select.gd`.

Node tree + key properties:
- `Control` "MapSelect" (full rect, theme = lota_theme, script = map_select.gd)
  - `ColorRect` "Sky" — full rect, `mouse_filter = 2` (IGNORE). Give it a vertical gradient: use a `GradientTexture2D` on a `TextureRect` instead, top `Color("e8842c")` (HORIZON_AMBER) → bottom `Color("1b1230")` (DUSK_PURPLE). (A `TextureRect` "Sky" full-rect with a `GradientTexture2D` whose `Gradient` has those two stops; `fill_from=(0,0) fill_to=(0,1)`.)
  - `TextureRect` "Halftone" — full rect, `texture = res://assets/hud/halftone_tile.png`, `stretch_mode = 1` (tile / `STRETCH_TILE`), `modulate = Color(1,1,1,0.06)`, `mouse_filter = 2`.
  - `SkewPanel` "Header" — offset rect at top (`x 16, y 12, w 1248, h 74`), `fill_color = Color("14101d")`, `mouse_filter = 2`. Children (all `Label`, `mouse_filter=2`):
    - "Title" text `MAP SELECT` (BebasNeue via theme, font_size 52, white) at ~(28, 8).
    - "Subtitle" text `// STAGE SELECTION` (font_size 22, `Color("f5b431")`) at ~(250, 26).
    - "FighterTag" text `FIGHTER:` (font_size 22, `Color("9a8f7a")`) right side ~(980, 26).
    - "FighterValue" (font_size 22, `Color("22d3ee")`) at ~(1090, 26).
  - `Node2D` "MapContainer".
  - `SkewPanel` "Tooltip" — offset rect top-right (`x 900, y 100, w 360, h 230`), `accent_color = Color("22d3ee")`, `header_height = 42`, `mouse_filter = 2`. Children `Label` (mouse_filter=2):
    - "Title" `NORTHERN LUZON` placeholder at (16, 8), font_size 22, white.
    - "RegionNum" `REGION 2` at (250, 12), font_size 16, `Color("9a8f7a")`.
    - "StageLabel" `STAGE` at (16, 52), font_size 14, `Color("9a8f7a")`.
    - "StageValue" placeholder at (16, 70), font_size 22, white.
    - "UnlocksLabel" `UNLOCKS` at (16, 104), font_size 14, `Color("9a8f7a")`.
    - "UnlocksValue" at (110, 104), font_size 18, `Color("22d3ee")`.
    - "StoryLabel" `STORY CONTEXT` at (16, 132), font_size 14, `Color("9a8f7a")`.
    - "StoryValue" at (16, 152), font_size 15, `Color("ede3ce")`, `autowrap_mode = 3` (WORD_SMART), `custom_minimum_size = (328, 0)`.
  - `SkewPanel` "ConfirmHub" — offset rect bottom-right (`x 900, y 350, w 360, h 200`), `fill_color = Color("14101d")`, `mouse_filter = 2`. Children:
    - `Label` "SelectedLabel" `SELECTED STAGE` at (16, 8), font_size 14, `Color("9a8f7a")`, mouse_filter=2.
    - `Label` "StageValue" placeholder at (16, 26), font_size 22, `Color("b366ff")`, mouse_filter=2.
    - `ColorRect` "ArtPlaceholder" at (16, 60, w 328, h 70), `Color(0.1,0.08,0.14,1)`, mouse_filter=2 (stage-art placeholder).
    - `Button` "ConfirmButton" text `CONFIRM SELECTION` at (16, 140, w 328, h 48), `pivot_offset = (164, 24)`, `self_modulate = Color("b366ff")`.

(Exact pixel offsets are guides — match `.local/map-select-sample.png`; nudge in the editor.)

- [ ] **Step 3: Launch the scene and verify visually**

Run: `godot --path . res://scenes/map_select.tscn`
Expected: dusk-gradient screen; the 5 regions render as the Philippines silhouette; Visayas is lifted/purple by default; hovering a region lifts it, tints it its accent, updates the tooltip + `FIGHTER:` breadcrumb; clicking selects; pressing CONFIRM turns the button green → `STAGE LOCKED IN` → loading screen. Fix layout/positions against `.local/map-select-sample.png`.

- [ ] **Step 4: Commit**

```bash
git add scenes/map_select.tscn scripts/map_select.gd
git commit -m "feat(map): map_select screen with region rendering + interaction [7.6]"
```

---

## Task 6: Route the flow through map_select; retire grid stage_select

**Files:**
- Modify: `scripts/character_select.gd:250`
- Delete: `scenes/stage_select.tscn`, `scripts/stage_select.gd`, `scripts/stage_select.gd.uid`, `stages/dojo/`, `stages/warehouse/`

**Interfaces:**
- Consumes: `scenes/map_select.tscn` (Task 5).

- [ ] **Step 1: Repoint character_select**

In `scripts/character_select.gd`, change the confirm transition:
```gdscript
	get_tree().change_scene_to_file("res://scenes/map_select.tscn")
```
(was `res://scenes/stage_select.tscn`).

- [ ] **Step 2: Confirm nothing else references the retired files**

Run:
```bash
cd /home/jacob/LOTA
grep -rn "stage_select\|stages/dojo\|stages/warehouse\|dojo_data\|warehouse_data" --include=*.gd --include=*.tscn --include=*.tres . | grep -v "scripts/stage_select.gd\|scenes/stage_select.tscn"
```
Expected: no output. If any reference remains (e.g. a test), update or remove it before deleting.

- [ ] **Step 3: Delete the retired files**

```bash
cd /home/jacob/LOTA
rm -f scenes/stage_select.tscn scripts/stage_select.gd scripts/stage_select.gd.uid
rm -rf stages/dojo stages/warehouse
ls tests | grep -i stage   # if a stage_select test exists, remove it too
```

- [ ] **Step 4: Verify the game still boots and the flow links**

Run: `godot --headless --path . --quit`
Expected: no load errors mentioning `stage_select`, `dojo`, or `warehouse`. Then spot-check: `godot --path . res://scenes/character_select.tscn`, confirm characters → lands on the map select screen.

- [ ] **Step 5: Commit**

```bash
git add scripts/character_select.gd scenes/stage_select.tscn scripts/stage_select.gd scripts/stage_select.gd.uid stages/dojo stages/warehouse
git commit -m "feat(map): route stage picking through map_select; retire grid stage_select [7.6]"
```

---

## Task 7: Headless integration test

**Files:**
- Create: `tests/test_map_select.gd`

**Interfaces:**
- Consumes: `data/map_regions.json`, `scenes/map_select.tscn`, `MatchSelection`.

- [ ] **Step 1: Write the test**

Create `tests/test_map_select.gd`:
```gdscript
extends SceneTree
## Headless integration check for map select (7.6): baked data integrity + the
## confirm handoff (sets MatchSelection.stage_data, emits stage_confirmed).

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

	# --- confirm handoff ---
	MatchSelection.stage_data = null
	var scene: PackedScene = load("res://scenes/map_select.tscn")
	var screen: Node = scene.instantiate()
	get_root().add_child(screen)
	screen.stage_confirmed.connect(func(id: int, stage: String, fighter: String) -> void:
		_emitted = [id, stage, fighter])
	screen.select_region(3)          # Metro Manila
	screen.lock_selection()
	_check(MatchSelection.stage_data != null, "confirm set MatchSelection.stage_data")
	_check(MatchSelection.stage_data != null and MatchSelection.stage_data.stage_name == "Barangay Boxing Ring",
		"stage_data is the selected region's stage")
	_check(_emitted.size() == 3 and _emitted[0] == 3, "stage_confirmed emitted with region id 3")
	_check(_emitted.size() == 3 and _emitted[2] == "Dirty Boxing Fighter", "stage_confirmed carries the fighter")
	screen.queue_free()

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
```

- [ ] **Step 2: Run the test**

Run: `godot --headless --path . --script res://tests/test_map_select.gd`
Expected: all PASS, `0 failures`. (If instantiating the scene headless errors on `physics_object_picking`, that call is harmless headless; if it throws, guard it in `map_select.gd._ready` with `if get_viewport(): get_viewport().physics_object_picking = true`.)

- [ ] **Step 3: Commit**

```bash
git add tests/test_map_select.gd
git commit -m "test(map): map_regions integrity + confirm handoff [7.6]"
```

---

## Self-Review notes

- **Spec coverage:** data pipeline (T1), 5 regions/groupings/dissolve/projection/speck-drop (T1), baked resource w/ all fields incl. label_anchor (T1), 5 StageData (T2), skewed bordered panels w/ shadow (T3), region fill+outline+glow+shadow+Area2D hit-test+comic labels+uniform lift tween (T4), sky gradient+halftone+header+tooltip+ConfirmHub+confirm scale/lock/green/signal (T5), default Visayas (T5), replace-flow integration + retire (T6), tests (T2, T7). Covered.
- **Placeholders:** none — every code step is complete.
- **Type consistency:** `MapRegion.setup(data)`, `set_active`, `set_base_y`, `region_hovered`/`region_clicked`, `SkewPanel` exports, and `map_select.gd`'s `select_region`/`lock_selection`/`stage_confirmed` names match across T4–T7.
- **Known soft spots to watch during execution:** (a) `MIN_AREA_PX` may need tuning if a wanted island vanishes or specks remain (T1 step 4); (b) exact panel pixel offsets are guides to reconcile against `.local/map-select-sample.png` (T5 step 3); (c) Area2D physics picking under a full-rect Control relies on overlay Controls being `mouse_filter=IGNORE` and `physics_object_picking=true` (set in T5).
