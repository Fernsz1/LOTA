# Map Select — Hi-Fi Redesign (7.6)

**Date:** 2026-07-05
**Status:** Design approved, pending implementation plan
**Source of truth:** `.local/README.md` + `.local/art_direction_reference.png` (handoff doc, UTF-8) + `.local/01_map_screen_default.png`

## Overview

Rebuild the Map Select screen to the hi-fi handoff spec: a stylized, cel-shaded
(Borderlands-style) rendering of the Philippine archipelago tilted in an elevated
parallax view, split into 5 playable macro-regions. Hovering a region scouts its
stage; clicking locks it in; a chunky **CONFIRM SELECTION** button commits the pick.

The current screen is a flat GeoJSON-projected map with hover-recolor + a label.
This redesign layers the full art direction on top of that pipeline **without a 3D
subsystem** — the tilt is faked with a 2D affine transform so the existing 2D
generator and point-in-polygon hit-testing carry over. Chosen for visual quality
with no lag risk in a pure-2D project.

## Goals

- Recreate the 4 separable layers of the handoff at hi-fi.
- Reuse the existing map geometry pipeline (generator bake, Douglas-Peucker
  simplified rings, geometric hit-testing).
- Keep region list, colors, and copy in one data structure for easy tweaking.
- No per-frame heavy work — static draws + interaction-only tweens.

## Non-Goals

- Real 3D (SubViewport + Camera3D + meshes) — rejected for lag/risk in a 2D game.
- True perspective foreshortening — the affine fake is sufficient for the stylized look.
- Final 16:9 stage preview art (a clearly-marked placeholder slot is left instead).
- Fighter roster art (out of scope for this screen).

## Architecture — 4 Layers

Kept cleanly separable per the handoff.

```
MapSelection.tscn (root: MapRoot, Node2D, map_manager.gd)
├── Background   (flat,   z0)    dusk-ocean gradient: ColorRect + shader
├── MapPlane     (Node2D, z1)    affine tilt; parents the 5 region nodes
│     ├── NorthernLuzon  (Node2D)  extruded landmass + fill/stroke
│     ├── CentralLuzon   (Node2D)
│     ├── SouthernLuzon  (Node2D)
│     ├── Visayas        (Node2D)
│     └── Mindanao       (Node2D)
├── Markers      (Control, z30)   beacons + upright light-beams (screen space)
└── UI           (CanvasLayer, z40+)  header · info panel · stage preview · confirm · ribbon
```

- `map_manager.gd` remains the runtime controller AND the single source of truth
  for region grouping + metadata.
- `map_generator.gd` (`@tool`) remains the edit-time baker; extended to draw the
  extruded double-pass + hard shadow.

### Layer 1 — Background: Dusk Ocean (z0, flat)

Full-bleed painterly sunset over water, built from stacked gradients in a shader
(no bitmap plate — the handoff's `art_direction_reference.png` is a text doc, not
an image). A `ColorRect` sized to the viewport with a fragment shader reproducing:
- sky→ocean vertical gradient (`#1c130d`→…→`#071118`, stops per handoff §Layer 1),
- warm sun glow ellipse at (50%, 30%),
- 3 distant island humps on the horizon (~top 33%),
- faint water-sheen streaks (screen blend) from ~46% down,
- a vignette (`radial`, transparent center → `rgba(4,10,14,.72)` edges).

### Layer 2 — Map Plane (z1, tilted)

A `Node2D` "MapPlane" carrying the affine tilt:
- rotation `-20°` (comic-book diagonal),
- `scale.y = cos(49°) ≈ 0.656` (fakes the elevation/parallax tilt),
- centered/positioned to frame the archipelago in the 1280×720 base viewport.

The tilt is a single static transform — zero per-frame cost.

### Layer 3 — Regions (children of MapPlane, inherit the tilt)

5 region `Node2D`s (reuse current bake, named by macro-region id). Each region's
`Visual` holds, per ring:
1. **Underside/side wall:** the ring polygon offset +Y (post-tilt down), dark fill
   `#2a2612`, thick dark stroke — drawn behind the top face for the extruded edge.
2. **Top face:** the ring polygon, fill = region base color, stroke = region stroke
   (neon-driven at runtime), thick round-join stroke, `outline.gdshader`.
3. **Hard cast shadow:** an offset dark-transparent copy (`rgba(4,3,1,.9)`), no blur.

Hit-testing: `Geometry2D.is_point_in_polygon` on the top-face polygons, evaluated in
**MapPlane-local space** — the manager inverse-transforms the global mouse position
through MapPlane before testing, so the affine tilt does not shift the hit area.

### Layer 4 — Overlay UI (z40+, flat screen space) + Markers (z30)

- **Markers (Control, z30):** per region, positioned at its centroid projected
  through MapPlane's transform into screen space (so they track the tilted land but
  render upright): pulsing halo (`pulseBeacon`), core dot (`corePulse`), and a
  3-cone upright light-beam (`beamPulse`). Beams stand upright for free because they
  live in flat space — no counter-rotation math.
- **Header (top, h≈104):** `MAP SELECT` (display font, ~42px, letter-spacing 9) +
  `FIGHTER: <name>` sub-line (gold `#ffcf3f` name).
- **Info panel (top-right, skew -2°):** 5px `#0a0904` border, dark gradient fill,
  hard shadow, top accent strip (state-colored), kicker
  (`HOVER · SCOUTING` / `LOCKED IN` / `STANDBY`), region name + `(REGION n)`,
  dashed divider, FIGHTER/STAGE/CONTEXT grid.
- **Stage preview (bottom-right, skew -2°):** 158px striped placeholder with a
  state-colored inner glow and a clearly-marked `[ drop stage art · 16:9 ]` slot.
- **Confirm button (bottom-right, skew -3°):** notched corners (`clip-path`
  equivalent via a stylebox/polygon), disabled (grey) vs enabled (gold) states.
- **Confirmation ribbon (center, z60):** purple `#b154ff` slab, skew -5°, `STAGE
  LOCKED` + stage name, `ribbonIn` animation ~1.55s then auto-dismiss.

## Data — Region Metadata (single source of truth)

`map_manager.gd` `REGIONS` extended; grouping (`GROUPS`, by adm1_pcode) unchanged and
already correct. **Stage mapping corrected to the handoff table** (Central/Visayas/
Mindanao were shuffled):

| id | index | display | base | neon | neon_stroke | fighter | stage (.tres) | story |
|---|---|---|---|---|---|---|---|---|
| NorthernLuzon | 1 | NORTHERN LUZON | `#3f6f92` | `#34b0ff` | `#bfe6ff` | BUNO | `mountain_festival` | Highland grapplers forged in the festivals of the Cordillera ranges. |
| CentralLuzon | 2 | CENTRAL LUZON | `#a8432f` | `#ff5a3c` | `#ffc7ba` | DIRTY BOXING | `barangay_ring` | Street-hardened brawlers trading blows in the barangay rings. |
| SouthernLuzon | 3 | SOUTHERN LUZON | `#5c8038` | `#84e23c` | `#d9ffb2` | ARNIS | `bahay_kubo` | Stick-and-blade masters drilling in the southern training yards. |
| Visayas | 4 | VISAYAS | `#6b4a9c` | `#b154ff` | `#e2c2ff` | SIKARAN | `heritage_plaza` | Sikaran was born from freedom and resilience in the island heartland. |
| Mindanao | 5 | MINDANAO | `#c0982f` | `#ffd23a` | `#fff1b0` | SEPAK TAKRAW | `beach_court` | Airborne acrobats who settle every score on the dusk-lit shore. |

Full stage paths: `res://stages/<id>/<id>_data.tres`. Centroid per region computed at
bake time (area-weighted mean of top-face polygons) and stored for marker placement.

## Interactions (state machine)

State: `hover` (id|null), `selected` (id|null), `confirmed` (id|null).

- **Hover:** wrapper elevates (Y-lift + slight scale, spring `.22s`
  `cubic-bezier(.34,1.4,.5,1)`); top-face stroke → gold `#ffd24a`, fill → `#a7a24b`,
  marker color → gold; hard shadow grows; info panel → `HOVER · SCOUTING`, accent
  gold, populated with the hovered region's fighter/stage/story.
- **Select (click):** top face → region neon + neon stroke + neon glow; marker →
  neon; header `FIGHTER:` shows the fighter; panel kicker → `LOCKED IN`, accent →
  neon; CONFIRM becomes enabled.
- **Hover priority:** while hovering, panel/accent reflect the hovered region; the
  selected region keeps its neon look underneath.
- **Confirm** (enabled only when `selected != null`): show center ribbon ~1.55s,
  then hand off to the existing `_select()` navigation (loading_screen, or
  training.tscn when `MatchSelection.training`).
- **Transitions:** region transform/filter `.22s` spring; fill/stroke `.18s`;
  button `.15s`.

## Design Tokens (hi-fi, final)

- **Ink/outlines:** `#0a0904`; land underside `#2a2612`.
- **Region base:** `#3f6f92 #a8432f #5c8038 #6b4a9c #c0982f`.
- **Region neon:** `#34b0ff #ff5a3c #84e23c #b154ff #ffd23a` (+ pale strokes above).
- **Hover:** accent `#ffcf3f`, rim `#ffd24a`, land fill `#a7a24b`.
- **UI dark:** panel `#181b21`→`#0e1116`, strip idle `#4a5058`, text
  `#eef1f5 / #c4ccd4 / #7f8a95`, gold value `#ffcf3f`. Ribbon `#b154ff` on `#0a0904`.
- **Depth (blur-free/hard):** region idle `7,12`, hover `11,28`, select `9,21`;
  panels `11,13` / `8,10`; confirm `6,8` off / `8,11` on. Neon "pop" glows are the
  only soft shadows.
- **Borders:** panels/buttons 5px (ribbon 6px); land top stroke ~7px, side ~9px.
- **Skew:** panel/preview -2°; confirm -3°; ribbon -5°.
- **Fonts:** display = **Anton** (fallback Impact-class); body = **Oswald**
  (400–700). Added to `art/fonts/` for fidelity; if absent, fall back to the repo's
  **BebasNeue**. FontFile refs kept swappable.
- **Motion:** region pop `.22s cubic-bezier(.34,1.4,.5,1)`; color `.18s`; button
  `.15s`; `pulseBeacon 2.6s`, `corePulse 2.2s`, `beamPulse 2.2s` (staggered),
  `ribbonIn 1.6s`.

## Testing (headless SceneTree scripts)

Extend the existing suite:
- **Data:** 5 regions; each has base/neon/stroke/fighter/stage/story; stage `.tres`
  exists; stage mapping matches the spec table (regression for the shuffle bug).
- **Bake:** region roots are Node2D with a Visual holding top-face + underside +
  shadow Polygon2D layers and stroke Line2D; no CollisionPolygon2D; centroid stored.
- **Hit-testing:** an interior point of a region, transformed through MapPlane,
  resolves via `_region_at` to that region; a point far outside → null.
- **State:** `_apply_hover_in/out`, `_select` recolor to gold/neon/base and emit
  `region_selected` with the corrected (display, stage) pair; confirm gating.
- **Boot:** `MapSelection.tscn` boots headless with no script/parse/decompose errors.

## Performance

- Tilt is one static transform; extrusion/shadow are static extra draws at bake time.
- Tweens run only on hover/select/confirm; beacon/beam pulses are lightweight
  shader/tween loops on ≤5 markers.
- Reuses Douglas-Peucker simplified rings (≈121KB scene). No per-frame allocation.

## Open Items / Follow-ups

- Source Anton + Oswald TTFs (OFL) into `art/fonts/`; else BebasNeue fallback.
- 16:9 stage preview art (one per stage) — placeholder slot only for now.
- Optional painted sky plate to replace the gradient shader (not required).
