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

---

## 3. Attack states & hit resolution (2.3 / 2.4)

### Attack states (2.3)

A pressed attack button (`FAST` / `HEAVY`, buffered `ATTACK_BUFFER = 4` frames) while
actionable enters `FAST_ATTACK` / `HEAVY_ATTACK` and arms `_current_move` (a `MoveData`
assigned per-fighter via `@export move_fast` / `move_heavy` in `main.tscn`). Then, in
`character_controller.gd`:

- `_resolve_attack()` sets `active_hitboxes_local = _current_move.hitboxes_at(frame_in_state)`
  — hitboxes are live **only** on the move's active frames, empty otherwise.
- `_resolve_busy_exits` locks the character until `frame_in_state >= _current_move.total()`,
  then returns to `IDLE` (recovery is real — the move can't be cancelled in v1).
- `_move_has_hit` latches so one attack lands **at most one hit** (it survives the
  hitstop freeze); it clears when the next attack starts. `SKILL` is unbound for now.

### Hit resolution (2.4)

`main.gd._resolve_combat()` runs at physics priority 1 (after both controllers moved),
both attack directions, and **skips entirely while either fighter is frozen** (hitstop):

1. `attacker.get_active_move()` → the move whose hitbox can connect (null if none / already hit).
2. `CombatBoxes.overlaps(attacker hitboxes, defender hurtboxes)` (the 2.1 layer).
3. `HitResolver.classify(overlapping, defender.is_invulnerable(), guarding)` → `NONE / HIT / BLOCK`.
   - **Block model is hold-back** (2.4 decision — there is no block button): `HitResolver.is_guarding`
     = the defender is in an actionable ground state **and** holding the away-from-attacker
     direction. Stand-block (`WALK_B`) and crouch-block (`CROUCH`) both guard every v1 mid.
4. Apply: `apply_hitstop(move.hitstop)` to **both** (freeze), then `apply_block` (no damage,
   blockstun, more pushback) or `apply_hit` (damage, hitstun, pushback).

**Hitstop** pauses the whole character — input, movement, **and** `frame_in_state` — so the
impact freeze never counts as stun (feel-reference §4/§7). **Pushback** is `pushback_hit/block`
px/frame applied during `HITSTUN`/`BLOCKSTUN`, decaying by `PUSHBACK_DECAY` so a blocked string
spaces itself out. Stun lasts `move.hitstun` / `move.blockstun` frames, then → `IDLE`.

## 4. Knockdown, getup & reactions (2.5)

- A move with `causes_knockdown = true` (e.g. `heavy.tres`), or **any hit on an airborne
  defender**, forces `KNOCKDOWN` instead of `HITSTUN` (`apply_hit` → `on_launched()`).
- `KNOCKDOWN` (`KNOCKDOWN_FRAMES = 40`) → `GETUP` (`GETUP_FRAMES = 16`) → `IDLE`.
- **Wake-up invulnerability**: `is_invulnerable()` is true during `GETUP` (and `KO`); the
  resolver early-outs, so a meaty attack on a getting-up defender whiffs. Hurtboxes stay
  drawn for debug — invuln is enforced in resolution, not by hiding the box.
- The three reactions are distinct states with distinct durations/pushback: `HITSTUN`
  (got hit), `BLOCKSTUN` (guarded), `KNOCKDOWN` (launched / hard knockdown).

> **Known limitation (intentional for the 2.x milestone).** A grounded `KNOCKDOWN`
> fighter is **not** invulnerable, so a move can re-hit it on the floor — repeated
> knockdowns chain into an OTG ("off-the-ground") re-knockdown loop. This is okizeme /
> juggle-limit territory, deferred to the cancel/juggle system (3.5) and the balance
> pass (8.2). It does not block "a round can be won and lost". When addressed, the fix
> is a per-combo juggle/OTG limit or brief knockdown invuln — not a structural change.

## 5. Command grabs & throws (6.4)

Grabs reuse the strike pipeline's shapes but resolve on a **separate channel** so
blocking never protects and strike code never sees a grab box.

### Data (`MoveData`, same resource)

A move with `is_grab = true` (Jacob's SKILL/ULTIMATE) reinterprets its fields:
`hitboxes` become the **grab box** (connect window = active frames), `recovery` is
the whiff punish, `hitstun/blockstun` are unused. New fields: `throw_release_frames`
(length of the throw animation; damage lands at the end), `tech_window` (frames from
`GRABBED` entry where the victim's FAST press escapes; `0` = untechable) and
`throw_launch_y` (victim's vertical pop into `KNOCKDOWN` at release).

### States (FSM)

`GRAB_ATTEMPT` (busy; entered from actionable; exits to `IDLE` on whiff or
`THROW_RELEASE` on connect) / `GRABBED` (reaction, **forced** on the victim; exits
to `IDLE` on tech/abort or is force-launched by the slam) / `THROW_RELEASE` (busy;
exits to `IDLE`). Grabs are grounded-only: airborne states can't request
`GRAB_ATTEMPT`.

### Resolution (`GrabRules` decides, `ThrowSequencer` applies)

Mirrors the HitResolver split. `GrabRules.is_grabbable(state)`: grounded and NOT
prejump (`JUMP_START` — jumping escapes grabs), NOT in a reaction (no throw loops in
combos), NOT `GETUP`/`KO`/`THROW_RELEASE`. Blocking and attack recovery ARE
grabbable. `is_invulnerable()` is respected like strikes — and includes `GRABBED`
itself, so a held victim can't be struck by a stray projectile.

`ThrowSequencer` (one per scene in `main.gd`; one per arena in training) owns a
connected throw: hitstop both on connect, snap the victim to a hold offset (48px —
wider than the pushbox, so separation stays quiet; the scenes still pause pushbox
resolution during a throw to dodge the deep-overlap bounce), count
`throw_release_frames`, then damage + pop + forced `KNOCKDOWN` and release. The
**tech** lookback spans `tech_window + hitstop` frames because input buffers keep
filling during the connect freeze while the sequencer doesn't step. If either
fighter leaves its throw state early (projectile interrupt, round reset, timer KO)
the sequence aborts and frees whoever is still held.

Ordering per frame: strikes → throws → projectiles, so a same-frame trade favors
the strike (the grabber gets hit out of the attempt).

Verified end-to-end by `scenes/dev/grab_demo.tscn` (headless, exit 0 = pass) plus
`tests/test_grab_rules.gd`, `tests/test_fsm.gd`, `tests/test_jacob_load.gd`.
