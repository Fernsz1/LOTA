# Map Select — Fresh Rebuild (Borderlands aesthetic)

**Status:** design — awaiting user review
**Date:** 2026-07-05
**Branch:** `feat/7.6-map-select`
**Supersedes:** the existing `scripts/map_select.gd` + `scripts/ui/map_region.gd` +
`data/map_regions.json` implementation (fresh rebuild, replace).

An interactive 2D Map Select screen for LOTA. The player picks a stage by clicking
one of 5 macro-regions on a projected map of the Philippines. Gritty, cel-shaded,
graphic-novel art direction (Borderlands): thick solid **black ink outlines**
(zero blur), muted slate base fills, hyper-saturated neon pop on hover, aggressive
spring lift on hover.

---

## 1. Decisions (spec vs. repo reality)

| Topic | Decision | Rationale |
|---|---|---|
| Relation to existing | **Fresh rebuild, replace** | User directive. Retire old map-select files. |
| Hit-testing | **`Area2D → CollisionPolygon2D`** per spec | User directive. Godot auto-decomposes concave rings into convex sub-shapes for collision; `mouse_entered/exited/input_event` fire normally. |
| Resolution | **Project into 1920×1080** design space | User directive. `project.godot` is 1280×720 with `canvas_items` stretch, so it scales cleanly to the real window. |
| Data source | **`.local/philippines_optimized.json`**, read **edit-time only** | 7.4 MB GeoJSON, 17 admin regions, lat/lon MultiPolygons. `@tool` bakes nodes into the scene; runtime never opens it. `.local/` stays gitignored / unshipped. |
| Outline rendering | **`Line2D` ink borders** (Option A) | Borderlands look = thick sharp black strokes. Polygon2D solid fills have no texture alpha for a fragment outline shader to sample; baked `Line2D` gives crisp, animatable, zero-blur strokes. `outline.gdshader` still delivered per spec for textured fills. |
| Folder | **`res://scenes/ui/map_select/`** (dedicated feature folder) | Spec asks for one dedicated folder holding the three files + scene. |

---

## 2. Files

### New — `res://scenes/ui/map_select/`
- `map_generator.gd` — `@tool` script for `Node2D MapRoot`; edit-time node baker.
- `map_manager.gd` — runtime logic + animation for `MapRoot`.
- `outline.gdshader` — CanvasItem graphic-novel stroke shader (delivered per spec).
- `MapSelection.tscn` — wired scene.

### Retired (deleted in the rebuild)
- `scripts/map_select.gd` (+ `.uid`)
- `scripts/ui/map_region.gd` (+ `.uid`)
- `scenes/map_select.tscn`
- `data/map_regions.json`
- `scripts/dev/bake_map_regions.py` (+ `__pycache__`)
- `tests/test_map_select.gd` (+ `.uid`)

### Modified
- `scripts/character_select.gd:250` — repoint handoff to
  `res://scenes/ui/map_select/MapSelection.tscn`.

---

## 3. Projection math (`map_generator.gd`)

1. Walk every feature's MultiPolygon coordinate, collect `min/max` lon & lat → bbox.
2. Uniform scale to fit 1920×1080 with padding `PAD` (e.g. 80 px):
   `scale = min((1920 - 2*PAD) / lon_span, (1080 - 2*PAD) / lat_span)`.
3. Per point: `x = PAD + (lon - lon_min) * scale`,
   `y = PAD + (lat_max - lat) * scale`  (Y flipped for screen-down).
4. Center the fitted map within the viewport.

Equirectangular (no Mercator) — accurate enough at country scale, and the art is
stylized regardless.

---

## 4. Grouping — 17 admin regions → 5 macro-regions

Keyed by `properties.adm1_pcode` (verified against the JSON at build time; fall back
to `adm1_name` substring match if a pcode differs). Each macro-region maps to one of
the 5 existing stage `.tres` resources.

| Macro-region | `adm1_pcode` set | Stage `.tres` | Neon pop |
|---|---|---|---|
| Northern Luzon | PH01, PH02, PH14 (CAR) | `stages/mountain_festival/mountain_festival_data.tres` | `#ffd700` |
| Central Luzon | PH03, PH13 (NCR) | `stages/heritage_plaza/heritage_plaza_data.tres` | `#8a2be2` |
| Southern Luzon | PH04 (IV-A), PH17 (MIMAROPA), PH05 | `stages/bahay_kubo/bahay_kubo_data.tres` | `#ff2d55` |
| Visayas | PH06, PH07, PH08 | `stages/beach_court/beach_court_data.tres` | `#00e5ff` |
| Mindanao | PH09, PH10, PH11, PH12, PH16 (Caraga), PH19 (BARMM) | `stages/barangay_ring/barangay_ring_data.tres` | `#39ff14` |

Verified against the JSON: all 17 pcodes present; `PH13` (NCR) and `PH14` (CAR) are
GeoJSON `Polygon`, the other 15 are `MultiPolygon` — the parser handles both.

Base (unhovered) fill for all: `#343d46`.

---

## 5. MultiPolygon → node tree (baked by `map_generator.gd`)

Per macro-region:

```
Area2D  (name = region id, e.g. "NorthernLuzon")
├── Visual  (Node2D)              # tween target for the hover lift
│   ├── Polygon2D  (ring 0)       # muted slate fill, outline.gdshader material
│   ├── Line2D     (ring 0)       # thick black closed ink stroke
│   ├── Polygon2D  (ring 1) ...   # one pair per exterior ring (island)
│   └── Line2D     (ring 1) ...
└── CollisionPolygon2D (ring 0)   # one per exterior ring, feeds Area2D hit-testing
    CollisionPolygon2D (ring 1) ...
```

- **Exterior rings only.** Interior holes dropped for the stylized fill.
- **Island filter:** drop rings whose projected area < `MIN_AREA` (e.g. 8 px²) to
  keep node counts reasonable — the archipelago has many tiny islets.
- `Line2D`: `closed = true`, `width = outline_width`, `default_color = black`,
  `joint_mode = round`.
- All baked nodes get `set_owner(get_tree().edited_scene_root)` so they persist and
  serialize into the scene.
- `@export var build_map: bool` — setter runs the bake; `@export var clear_map: bool`
  wipes previously baked children (idempotent re-bake).

---

## 6. Runtime (`map_manager.gd`)

Replaces the `@tool` script on `MapRoot` for play mode.

- `signal region_selected(region_name: String, stage_name: String)`
- `_ready()`: iterate the 5 `Area2D` children; connect `mouse_entered`,
  `mouse_exited`, `input_event` in code (bind the Area2D each time).
- **Hover in:** `create_tween()` → `Visual.position.y` to `-15`,
  `set_trans(Tween.TRANS_SPRING)`, `set_ease(Tween.EASE_OUT)`; set each Polygon2D
  fill → the region's neon color; raise each Line2D width (crank the stroke).
- **Hover out:** tween `Visual.position.y` back to `0`; revert fill → `#343d46`;
  restore Line2D width.
- **Click** (`input_event`, `MOUSE_BUTTON_LEFT` pressed): `emit_signal(
  "region_selected", region_name, stage_name)`, set
  `MatchSelection.stage_data = load(stage_data_path)`, then
  `get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")`.

Region → (name, stage path, neon) metadata lives in a const dictionary keyed by the
Area2D node name, so runtime needs no JSON.

---

## 7. Scene & flow integration

`MapSelection.tscn`:
- `Node2D MapRoot` (`map_manager.gd`) with the 5 baked `Area2D` region subtrees.
- `CanvasLayer UI` — bold uppercase title ("SELECT YOUR BATTLEGROUND") + a region-name
  label that updates on hover.

Wire-in: `scripts/character_select.gd:250` →
`res://scenes/ui/map_select/MapSelection.tscn`. Downstream (`loading_screen →
character_intro → fight`) already consumes `MatchSelection.stage_data`, unchanged.

---

## 8. `outline.gdshader`

Godot 4.7 CanvasItem shader, delivered per spec:
- `uniform float outline_width = 6.0;`
- `uniform vec4 outline_color: source_color = vec4(0.0, 0.0, 0.0, 1.0);`
- Ring-samples `TEXTURE` alpha at `outline_width` in 8 directions; where the pixel is
  transparent but a neighbor is opaque, output solid `outline_color` (hard edge, no
  blur/gradient). Applies to any textured Polygon2D fill. (The crisp region borders
  themselves come from the baked `Line2D`s — the shader is the spec-requested,
  reusable fill outline.)

---

## 9. Testing

- Headless `--script` integration test: instantiate `MapSelection.tscn`,
  `await process_frame`, assert exactly 5 `Area2D` children each with ≥1
  `CollisionPolygon2D` and ≥1 `Polygon2D`, and that each region name resolves to an
  existing stage `.tres`.
- Assert `region_selected` fires with the right `(name, stage)` on a simulated click.

---

## 10. Out of scope (YAGNI)

- Interior polygon holes (lakes) in fills.
- Runtime GeoJSON parsing (edit-time bake only).
- Keyboard/gamepad navigation of regions (mouse-first for now).
- Halftone/skew panel polish beyond the base outline look (can follow later).
