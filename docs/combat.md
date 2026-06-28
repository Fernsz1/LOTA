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
properties (see §2 once it lands). For the frame numbers behind moves, see
`feel-reference.md`.
