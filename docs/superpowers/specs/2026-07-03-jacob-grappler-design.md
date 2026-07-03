# Jacob (Buno) — Grappler/Heavy — Design [6.4]

Design for `game.md` 6.4 (plus the 6.1 kit-lock for Jacob, since no 6.1 doc
existed). Placeholder-box build via the established pipeline; rig/animation
follows later per Phase 5/6 art flow.

## Constraints honored

- **Input map is locked**: `p{n}_left/right/up/down/fast/heavy/skill/ultimate`.
  There is **no grab button** — Jacob's grabs live on the SKILL and ULTIMATE
  slots. No project.godot changes.
- **Character format unchanged**: Jacob is a standard `CharacterData` bundle
  (`characters/jacob/`) with the same four move slots, so character select,
  loading, intro, and training pick him up with zero format work.
- **Frame data stays data**: grabs are authored in `MoveData` `.tres` files;
  no timing lives in scenes or rigs.
- **FSM extension follows docs/fsm.md's own 6.4 sketch**: `GRAB_ATTEMPT`
  (busy), `GRABBED` (forced reaction), `THROW_RELEASE` (busy → IDLE). No
  structural change to the machine.

## Archetype & stats

Slow, short-jumping, hits like a truck, wins by getting close.

| Stat | Jacob | Jerb | Rainne |
|---|---|---|---|
| walk_speed | 3.4 | 5.0 | 4.2 |
| walk_b_speed | 3.0 | 4.5 | 4.0 |
| jump_velocity | -13.5 | -13.0 | -12.5 |
| jump_f_speed | 2.6 | 3.5 | 3.0 |
| gravity | 0.72 (≈38f airtime) | 0.565 | 0.50 |
| max_health | **1150** | 1000 | 1000 |

`max_health` was authored-but-unread in v1. This change wires it through
(controller + match HUD fraction) so the tanky-grappler identity is real.
Jerb/Rainne keep 1000 — no behavior change for them.

## Kit (all four slots)

| Slot | Move | Numbers | Role |
|---|---|---|---|
| FAST | **Clinch Jab** | 5/3/12, dmg 55, hitstun 16, blockstun 11, hitstop 9, cancel 5–12 → HEAVY | Slower, stronger jab; his only quick button |
| HEAVY | **Hammer Swing** | 14/4/22, dmg 150, hitstun 24, blockstun 17, hitstop 14, **knockdown** | Committal haymaker |
| SKILL | **Buno Takedown** (command grab) | 7/4/26 whiff, dmg 180, hitstop 10, throw 30f, **tech window 10f** | The signature: unblockable, short range, very whiff-punishable |
| ULTIMATE | **Earthbreaker** (super grab) | 10/4/34 whiff, invuln 0–5, dmg 300, hitstop 16, throw 44f, **untechable** | Slow, armored-feeling (startup invuln) round-ender |

Grab boxes are shorter than his strikes (reach ≈ dx<70 vs dx<85), so spacing
answers him.

## Grab resolution flow

New pure/orchestration code in `scripts/combat/`, mirroring the
HitResolver-classifies / scene-applies split:

- **`GrabRules`** (static, headless-testable): `is_grabbable(state)` — a
  defender is grabbable iff **grounded** and not in `JUMP_START` (prejump is
  throw-invulnerable — jumping escapes grabs), not in a reaction state, not
  `GETUP`/`KO`/`GRABBED`/`THROW_RELEASE`. Blocking and attack-recovery ARE
  grabbable — that's the archetype's payoff. `is_invulnerable()` (getup/move
  invuln) is also respected.
- **`ThrowSequencer`** (RefCounted): owns one connected throw.
  - `try_start(attacker, defender)`: attacker in `GRAB_ATTEMPT` with the grab
    box live (active window, one-connect latch via `mark_move_hit`), AABB
    overlap vs hurtbox, defender grabbable → attacker → `THROW_RELEASE`,
    defender forced `GRABBED`, hitstop both.
  - `step()` (each unfrozen physics frame): validate the pair is still in
    `THROW_RELEASE`/`GRABBED` (anything else — e.g. a projectile interrupting
    the thrower, round reset, timer KO — **aborts and frees the victim**);
    snap victim to a hold offset in front of the attacker; within the move's
    `tech_window`, a buffered FAST press by the victim **techs**: both to
    IDLE, nudged apart, no damage; when `throw_release_frames` elapse, apply
    damage + vertical pop (`throw_launch_y`) + forced `KNOCKDOWN`, release
    attacker to IDLE.
- Grabs never consult guarding → **unblockable**. `GRABBED` victims are
  strike/projectile-invulnerable (no third-party interactions with the held
  body). Both match (`main.gd`) and training (`training_main.gd`) run
  sequencers; pushbox separation skips a paired couple.
- If both players grab on the same frame, P1's check resolves first (known,
  accepted v1 bias — same as the existing trade-check ordering).

## Data-layer additions (`MoveData`)

| Field | Default | Meaning |
|---|---|---|
| `is_grab` | false | SKILL/ULT slot arms `GRAB_ATTEMPT` instead of a strike state; hitboxes become the grab box |
| `throw_release_frames` | 30 | Length of `THROW_RELEASE`; damage lands at the end |
| `tech_window` | 8 | Frames from `GRABBED` entry where victim FAST techs; 0 = untechable |
| `throw_launch_y` | -6.0 | Victim vertical pop at release (falls into knockdown) |

`validate()` becomes grab-aware (skips the hitstun/blockstun inversion warning,
requires `throw_release_frames >= 1`). Existing strike moves are untouched —
all defaults preserve current behavior.

## FSM changes (`character_state_machine.gd`)

- Enum **appends** `GRAB_ATTEMPT, GRABBED, THROW_RELEASE` (existing values keep
  their ordinals).
- Requests: actionable → `GRAB_ATTEMPT`; `GRAB_ATTEMPT` → IDLE (whiff) |
  `THROW_RELEASE` (connect); `THROW_RELEASE` → IDLE; `GRABBED` → IDLE
  (tech/abort).
- Forces: `GRABBED` joins the force targets (victim entry); KNOCKDOWN/KO force
  out of `GRABBED` as from any non-KO state.
- Predicates: `is_busy` += GRAB_ATTEMPT/THROW_RELEASE; `is_in_reaction` +=
  GRABBED; `is_attacking` unchanged (strike-specific — grab boxes are read via
  a separate `get_grab_boxes()` so strike hit resolution never sees them).

## Controller changes (`character_controller.gd`)

- Arming: if the buffered SKILL/ULT move `is_grab`, request `GRAB_ATTEMPT`
  (same `_arm` path). Cancels never target grab moves (v1).
- Busy exits: `GRAB_ATTEMPT` whiffs to IDLE at `total()`. `THROW_RELEASE` and
  `GRABBED` are exited by the sequencer, not the controller.
- New API: `get_grab_boxes()`, `begin_throw()`, `end_throw()`,
  `apply_grabbed()`, `release_from_grab()`, `apply_throw(move, push_dir)`,
  `get_max_health()`.
- `is_invulnerable()` includes `GRABBED`; `_apply_movement` zeroes velocity in
  `GRABBED`/`THROW_RELEASE`.
- Health: `health`/round reset use per-character max (default 1000).

## Out of scope (deliberately)

- Hyper-armor on heavies (listed as "possible mechanic"; startup invuln on the
  ultimate covers the feel for v1).
- Cancels into command grabs; air grabs; side-switching throws.
- Rig/animation — placeholder boxes, per "feel first, animate last".

## Testing

- `tests/test_fsm.gd` extended with the new transition/predicate checks.
- `tests/test_grab_rules.gd` — pure grabbable-state matrix.
- `tests/test_jacob_load.gd` — bundle load/validate à la Rainne's.
- Live smoke: match scene with Jacob vs Jerb — grab connect, tech, whiff,
  ultimate, KO-by-throw.
