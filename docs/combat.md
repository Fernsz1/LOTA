# Combat

How LOTA detects and (later) resolves hits. This doc is built up across Phase 2:
§1 is the box layer (2.1); §2 is the frame-data / move format (2.2). Companion
docs: `conventions.md` (how we work), `feel-reference.md` (what good feel means
and the reference frame numbers), `fsm.md` (the character state machine).

All combat timing is in **frames at a fixed 60 Hz tick** — never seconds, never
`delta`. Gameplay runs in `_physics_process`.

---

## 1. Combat boxes (2.1)

The detection layer: manual AABB rectangles checked every physics frame. This
layer only **detects** overlap — real hit *resolution* (damage, stun, hitstop,
pushback) is 2.4 and consumes what is built here.

> **Why manual AABB, not `Area2D`?** Precise 2D fighters want frame-exact box
> tests with no physics-server signal latency. It's less code and more correct.
> We do **not** use `Area2D`/the physics server for combat boxes.

### Box-space convention (load-bearing — 2.3/2.4/4.3 rely on it)

- The character **origin is at the feet** (bottom-centre). The visual `Box` is
  `Rect2(-20, -80, 40, 80)`.
- Boxes are authored in **local, facing-right** space and **mirrored by `facing`
  at query time — X only, never Y.** The mirror math lives in one place:
  `CombatBoxes.to_world(local, origin, facing)` (`scripts/combat/combat_boxes.gd`).
- A box symmetric about x=0 (e.g. the body hurtbox) is unchanged by facing.

### The three box types

| Box | Color | Getter (world space) | Source |
|---|---|---|---|
| Hurtbox | **green** | `CharacterController.get_hurtboxes()` | `HURTBOX_STAND` / `HURTBOX_CROUCH` consts, by stance |
| Hitbox | **red** | `CharacterController.get_hitboxes()` | `active_hitboxes_local` (from move data in 2.3) |
| Pushbox | **yellow** | `CharacterController.get_pushbox()` | `PUSH_W`/`PUSH_H` (1.5 separation) |

The color code is the training-mode standard and is reused by the debug renderer
(`scripts/combat/combat_debug.gd`) and training mode (4.3).

### AABB border rule

Overlap uses `Rect2.intersects` with **borders excluded** — two boxes sharing
only an edge are **not** a hit. Pushback keeps bodies apart anyway, so this never
costs a legitimate contact.

### The empty-by-default early-out (perf)

`active_hitboxes_local` is **empty in the common case** (nobody attacking), so
`CombatBoxes.overlaps(a, b)` returns `false` immediately when either side is
empty. This is the real performance win — overlap checks cost ~nothing until a
hitbox is genuinely live. Keep that array empty unless a hitbox is truly active.

Other perf rules (from the plan's Global Constraints):
- Plain `Rect2` math; **no** physics server.
- Hurtboxes are local **consts**; hitboxes are a small reused array — no
  speculative per-frame allocation in the hot path.
- The debug renderer draws **only when enabled** and calls `queue_redraw()` from
  `_physics_process`.

### Detection vs resolution

`CombatBoxes.overlaps()` answers *"did a hitbox touch a hurtbox?"* — nothing
more. `combat_debug.gd` runs this each frame as a live demo and prints
`[2.1] CONTACT @ frame N` (edge-triggered, once per contact). The actual
consequence of a hit is **2.4**, using these same overlaps plus the `MoveData`
properties (see §2). For the frame numbers behind moves, see `feel-reference.md`.

---

## 2. Move / frame-data format (2.2)

A move's frame data is a Godot `Resource` (`MoveData`,
`scripts/combat/move_data.gd`) saved as a `.tres`. It is the **authoritative**
combat layer — animation syncs on top of it, never the reverse (see
`conventions.md` → "How frame data is authored" for the authoring workflow; this
doc describes the schema). Frames are integer @60Hz.

### Fields

| Field | Unit | Note |
|---|---|---|
| `move_name` | — | Identifier, used in validation messages. |
| `startup` | frames | Frames before the hitbox goes live (≥0). |
| `active` | frames | Frames the hitbox is live (≥1). |
| `recovery` | frames | Frames after active before actionable (≥0). |
| `hitboxes` | `Array[Rect2]` | **Local, facing-right**; live every active frame. Controller mirrors via `CombatBoxes`. |
| `damage` | hp | ≥0. |
| `hitstun` | frames | Stun applied on hit. |
| `blockstun` | frames | Stun applied on block. |
| `hitstop` | frames | Freeze applied before stun (feel-reference §4). |
| `pushback_hit` | px/frame | Pushback on hit. |
| `pushback_block` | px/frame | Pushback on block; block ≥ hit. |

### Frame convention (0-indexed `is_active`)

`frame_in_state` is **0 on the entry frame** (FSM contract), so for a move with
`startup = S`, `active = A`:

- startup frames are `0 .. S-1`
- the **first active frame is `S`** (the "S+1"-th frame in 1-indexed
  feel-reference §3)
- active frames are `S .. S+A-1`; recovery begins at `S+A`

`hitboxes_at(frame_in_state)` returns the live boxes (or empty) — callers read
through it so storage can change later without them changing.

### Derived advantage (never stored)

`on_block` / `on_hit` are **computed, not authored** — storing them would let them
drift from the frame data. Assuming a first-active-frame contact (hitstop cancels
out and is ignored):

```
on_block = blockstun - ((active - 1) + recovery)
on_hit   = hitstun   - ((active - 1) + recovery)
```

**Worked example — the sample jab** (`characters/jerb/moves/jab.tres`):
`startup 3 / active 2 / recovery 7`, `hitstun 13`, `blockstun 9`.
- `on_block = 9 - ((2-1) + 7) = 9 - 8 = +1`
- `on_hit   = 13 - ((2-1) + 7) = 13 - 8 = +5`

These match feel-reference §6 (light jab: +1 on block, ≈+5 on hit).

### `validate()` rules

Call after `load()` (2.3). Returns `false` on hard errors (and `push_error`s):
`startup<0`, `active<1`, `recovery<0`, empty `hitboxes`, or any negative
`damage`/`hitstun`/`blockstun`/`hitstop`. It also `push_warning`s (but stays
valid) when `hitstun <= blockstun`, which inverts the block incentive
(feel-reference §7).

### Sample location & ratified decisions

- **Moves live per-character: `/characters/<name>/moves/`.** (conventions
  open-decision #1 → per-character, now ratified). The sample is
  `characters/jerb/moves/jab.tres`. Moves are **not** in `/data`.
- **`on_block`/`on_hit` are derived, never stored** (conventions
  open-decision #2 → derive, now ratified).

### Extending to multi-hit (future)

v1 stores **one** hitbox set live across the whole active window. To add multi-hit
later **without touching single-hit moves or callers**: add an optional
`active_windows: Array` (each entry a frame range + its own hitboxes) and make
`hitboxes_at()` prefer it when non-empty, falling back to the flat `hitboxes`.
Because every consumer already reads through `is_active()` / `hitboxes_at()`, the
seam absorbs the change.
