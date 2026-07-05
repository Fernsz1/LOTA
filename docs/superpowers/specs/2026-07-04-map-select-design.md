# Map Select / Stage Selection — Design

**Status:** approved (design)
**Date:** 2026-07-04
**Branch:** `feat/7.6-map-select` off `dev` (phase number provisional — align with the
current plan phase before opening the branch)

An interactive Map Select screen for LOTA (Legends of The Archipelago). The player
picks a stage by selecting one of 5 clickable regions on an accurate map of the
Philippines. Gritty cel-shaded / graphic-novel art direction (Guilty Gear Strive /
Borderlands): thick irregular black borders, hard-offset black drop shadows, bold
uppercase headers, halftone texture, slightly skewed panels.

This screen **replaces** the existing grid-based `stage_select` in the live match
flow.

---

## 1. Decisions & deviations from the original brief

| Topic | Decision | Rationale |
|---|---|---|
| Resolution | Design at **native 1280×720**, not 1920×1080 | `project.godot` is 1280×720, `canvas_items` stretch, `expand` aspect. "Fit the resolution of the game." |
| Script location | `scenes/map_select.tscn` + **`scripts/map_select.gd`** | Matches repo convention (`docs/conventions.md`: shared scripts under `/scripts`; `stage_select` follows this). Deviates from the brief's literal `scenes/map_select.gd`. |
| Baked format | **`data/map_regions.json`** (not `.tres`) | JSON is one of the two brief-sanctioned formats. Python→JSON is robust; hand-writing Godot `.tres` (script sub-resources + `PackedVector2Array` literals) from Python is fragile. Runtime loads pre-baked polygons — never parses GeoJSON. |
| Integration | **Replace live flow** | `character_select → map_select → loading_screen`, populate `MatchSelection.stage_data`, author 5 region `StageData`, retire old `stage_select`. |
| Geometry bake | **Vendor GeoJSON + commit script + commit baked JSON** | Fully reproducible offline; runtime only loads the baked JSON. |
| Fonts | `BebasNeue-Regular.ttf` (titles/headers), `Bangers-Regular.ttf` (region labels) | Already in `art/fonts/`. BebasNeue is the heavy condensed Anton substitute; Bangers is the comic display face for outlined region lettering. No new fonts sourced. |
| Halftone | Reuse `assets/hud/halftone_tile.png` | Already exists from HUD work. |

---

## 2. The 5 game regions

Grouping of the 17 PSGC admin regions → 5 game regions (dissolve internal province
borders within each group). PSGC region codes are the 10-digit codes; source files
are `provdists-region-<code-without-leading-zero>.0.001.json`.

| id | display_name | region_number | Admin regions (PSGC) | stage_name | fighter_name | accent |
|---|---|---|---|---|---|---|
| 1 | Luzon | 1 | CALABARZON `0400000000`, MIMAROPA `1700000000`, Bicol `0500000000` | Bahay Kubo Training Yard | Arnis Fighter | gold `#f5b431` |
| 2 | Northern Luzon | 2 | Ilocos `0100000000`, Cagayan Valley `0200000000`, CAR `1400000000` | Mountain Festival Grounds | Buno Fighter | cyan `#22d3ee` |
| 3 | Metro Manila | 3 | Central Luzon `0300000000`, NCR `1300000000` | Barangay Boxing Ring | Dirty Boxing Fighter | red `#ef4444` |
| 4 | Visayas | 4 | W/C/E Visayas `0600000000`/`0700000000`/`0800000000` | Heritage Plaza | Sikaran Fighter | purple `#b366ff` |
| 5 | Mindanao | 5 | IX `0900000000`, X `1000000000`, XI `1100000000`, XII `1200000000`, Caraga `1600000000`, BARMM `1900000000` | Beach Court at Dusk | Sepak Takraw Striker | orange `#fb7a2d` |

**Default selected: Visayas (id 4).**

Story context strings (baked verbatim):
- **Northern Luzon:** "In the highlands, strength is tested in fair combat. Buno is respect, balance, and honor."
- **Metro Manila:** "From makeshift rings in the barangays rise champions. Grit, heart, and never giving up."
- **Luzon:** "In a quiet village in Luzon, warriors train in secret, preserving the way of the rattan."
- **Visayas:** "Sikaran was born from freedom and resilience. Warriors honed their kicks to protect their people."
- **Mindanao:** "On coastal shores, every kick honors the players who made the Philippines a Sepak Takraw powerhouse."

---

## 3. Data pipeline (offline, committed)

### 3.1 Vendored source
`data/geojson_src/` holds the 17 lowres region GeoJSON files fetched from
`github.com/faeldon/philippines-json-maps` at
`2023/geojson/regions/lowres/provdists-region-<code>.0.001.json`. Committed so the
bake is reproducible without network.

### 3.2 `scripts/dev/bake_map_regions.py`
Pure-Python (stdlib only), run offline. Steps:

1. **Load** each group's GeoJSON province polygons (each feature is a Polygon or
   MultiPolygon of `[lon, lat]` rings).
2. **Dissolve** each group to one silhouette via directed-edge cancellation:
   - For every province ring, emit directed edges `(v[i] → v[i+1])` following the
     ring's winding. Round coordinates (~6 decimals) into a hashable key.
   - An internal shared border appears as `a→b` in one province and `b→a` in the
     neighbor. Cancel any edge whose reverse also exists.
   - Stitch surviving edges into closed rings by chaining `a→b, b→c, …` until
     return to start. A group may yield multiple rings (separate islands) — keep
     all that survive the area filter.
3. **Drop speck islands**: discard rings whose absolute shoelace area is below a
   small threshold (tuned so major islands survive, tiny specks vanish).
4. **Project** with a shared equirectangular projection over the bounding box of
   **all** included regions: `midLat = (latMin+latMax)/2`;
   `x = (lon − lonMin) · cos(midLat) · k`; `y = (latMax − lat) · k`. Choose `k` to
   fit a normalized map box preserving aspect (single `k` for both axes, using the
   binding dimension). Emit polygons in this normalized pixel space with origin at
   `(0,0)`.
5. **Label anchor** per region: centroid of its largest ring in projected space
   (manually overridable via a small dict in the script if a centroid lands off the
   silhouette).
6. **Emit** `data/map_regions.json`.

### 3.3 `data/map_regions.json` schema
```json
{
  "map_size": [w, h],
  "regions": [
    {
      "id": 4,
      "display_name": "Visayas",
      "region_number": 4,
      "stage_name": "Heritage Plaza",
      "fighter_name": "Sikaran Fighter",
      "story_context": "…",
      "accent_color": "#b366ff",
      "stage_data_path": "res://stages/heritage_plaza/heritage_plaza_data.tres",
      "label_anchor": [x, y],
      "outline_polygons": [[x0,y0, x1,y1, …], [ … ]]
    }
  ]
}
```
`outline_polygons` is an array of flat float arrays (one per ring); the runtime
converts each to a `PackedVector2Array`.

---

## 4. Runtime scene & rendering

### 4.1 `scenes/map_select.tscn`
Root `Control`, full-rect anchored to expand, 1280×720 design. Static chrome authored
in the scene; the map is built at runtime. Tree:

- **Root** `Control` (`scripts/map_select.gd`)
  - **Sky** `ColorRect` — vertical gradient `HORIZON_AMBER → DUSK_PURPLE` (`UIPalette`).
  - **Halftone** `TextureRect` — `assets/hud/halftone_tile.png`, tiled, low opacity;
    optional diagonal-stripe overlay at low opacity.
  - **Header** `SkewPanel` — `MAP SELECT` (BebasNeue) + accent `// STAGE SELECTION`,
    right-aligned `FIGHTER: <name>` breadcrumb.
  - **MapContainer** `Node2D`, centered — populated at runtime with region nodes.
  - **Tooltip** `SkewPanel` (top-right) — accent header + `NAME (REGION n)`, `STAGE`,
    `UNLOCKS: <fighter>`, `STORY CONTEXT`.
  - **ConfirmHub** (bottom-right) — `SELECTED STAGE` name + stage-art placeholder box
    + `CONFIRM SELECTION` button.

### 4.2 `scripts/ui/skew_panel.gd`
Reusable `@tool`-annotated `Control` that draws a slightly-skewed parallelogram:
hard black offset shadow → fill → thick black border, plus an optional accent header
strip. Exposed props: `skew_px`, `fill_color`, `accent_color`, `shadow_offset`,
`border_width`, `header_height`. Text nodes are layered as children on top.

### 4.3 `scripts/ui/map_region.gd`
One instance per region, built from a baked region entry. Owns:
- **Shadow**: offset dark `Polygon2D`(s), drawn behind.
- **Fill**: `Polygon2D` per ring (Godot auto-triangulates concave rings).
- **Outline**: `Line2D` per ring — black, width ~4, `joint_mode` round, closed.
- **Glow**: a second wider `Line2D` per ring in the accent color, shown only when
  active, drawn under the black outline.
- **Hit-test**: `Area2D` with one `CollisionPolygon2D` per ring (same outline).
- **Label**: comic outlined text (`Bangers`) at `label_anchor`.

State API driven by the parent: `set_state(active: bool, accent: Color)`.
- **Resting**: fill `#63552f`, black outline, small hard shadow, no glow, y-offset 0.
- **Elevated** (active): `Tween` (~0.15s, `EASE_OUT`/`TRANS_BACK`) lifts the node
  `−16px` (identical for every region), fill → dark accent tint, glow on, shadow
  grows. Elevation is a uniform node `position.y` offset.

### 4.4 `scripts/map_select.gd`
- Loads `data/map_regions.json`, instantiates a `map_region.gd` per entry into
  `MapContainer`, positioned/scaled to fit the center map area from `map_size`.
- State: `hovered_id`, `selected_id` (default 4 = Visayas); `active = hovered or
  else selected`. Re-applies region states whenever either changes.
- **Hover** (`Area2D.mouse_entered`/`mouse_exited`): updates `hovered_id`, tooltip,
  and `FIGHTER:` breadcrumb.
- **Click** (`Area2D.input_event`): sets `selected_id`, updates ConfirmHub.
- **Confirm**: button scales to `0.94` on press (Tween) → `MatchSelection.stage_data
  = load(region.stage_data_path)` → button turns green, label → `STAGE LOCKED IN` →
  emits `stage_confirmed(region_id, stage_name, fighter)` →
  `get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")`.

**Signal:** `signal stage_confirmed(region_id: int, stage_name: String, fighter: String)`.

Interaction is UI/rendering only — no combat determinism concerns, so `_process`/
tween/`delta` are fine here (per `docs/conventions.md`, rendering-only concerns may
use `_process`).

---

## 5. Integration changes (replace flow)

- **`scripts/character_select.gd`** (line ~250): repoint
  `res://scenes/stage_select.tscn` → `res://scenes/map_select.tscn`.
- **Author 5 `StageData`** under `stages/`:
  `mountain_festival/`, `barangay_ring/`, `bahay_kubo/`, `heritage_plaza/`,
  `beach_court/` — each a `<id>/<id>_data.tres` with `stage_name` and
  `background_color`/`floor_color` derived from the region accent. Regions reference
  these by `stage_data_path`.
- **Retire** (delete): `scenes/stage_select.tscn`, `scripts/stage_select.gd` +
  `.uid`, the old `stages/dojo/` + `stages/warehouse/`, and any `stage_select` test.
  Confirm nothing else references them (grep) before deleting.

`main.gd` already consumes `MatchSelection.stage_data` (colors) — unchanged.

---

## 6. Testing (headless GUT)

`tests/test_map_select.gd`:
- **Baked data integrity**: `data/map_regions.json` loads; exactly 5 regions;
  each has ≥1 non-empty `outline_polygons` ring; `region_number`s = {1,2,3,4,5};
  `accent_color`s match the table; every `stage_data_path` loads as a `StageData`.
- **Confirm path**: constructing the screen with a selected region, invoking confirm
  sets `MatchSelection.stage_data` to the region's stage and emits `stage_confirmed`
  with `(region_id, stage_name, fighter)`.

Hover hit-testing (point-in-polygon via `Area2D`) is not unit-tested headless;
resource integrity + the confirm signal are the verifiable "done" criteria.

Run per `lota-godot-binary` memory (Godot 4.7 headless GUT).

---

## 7. File manifest

**New**
- `data/geojson_src/*.json` — 17 vendored lowres region GeoJSON.
- `scripts/dev/bake_map_regions.py` — offline bake.
- `data/map_regions.json` — baked output.
- `scenes/map_select.tscn`, `scripts/map_select.gd` — the screen.
- `scripts/ui/map_region.gd` — per-region visual/hit-test node.
- `scripts/ui/skew_panel.gd` — reusable skewed bordered panel.
- `stages/{mountain_festival,barangay_ring,bahay_kubo,heritage_plaza,beach_court}/<id>_data.tres`.
- `tests/test_map_select.gd`.

**Modified**
- `scripts/character_select.gd` — repoint to `map_select.tscn`.

**Deleted (retire)**
- `scenes/stage_select.tscn`, `scripts/stage_select.gd(.uid)`,
  `stages/dojo/`, `stages/warehouse/`, any stage_select test.

---

## 8. Commit plan (split logical commits, conventional)

1. `chore(map): vendor PH region geojson + bake script` — `data/geojson_src/`,
   `scripts/dev/bake_map_regions.py`, `data/map_regions.json`.
2. `feat(map): author 5 region StageData resources [7.6]` — new `stages/*`.
3. `feat(map): map_select screen with region rendering + interaction [7.6]` —
   scene, `map_select.gd`, `map_region.gd`, `skew_panel.gd`.
4. `feat(map): route stage picking through map_select; retire grid stage_select [7.6]`
   — repoint `character_select`, delete old files.
5. `test(map): map_regions integrity + confirm handoff [7.6]`.
