# 1.3 — Character FSM Architecture (Design Spec)

- **Task:** Phase 1.3 of `game.md` — "Character FSM architecture"
- **Date:** 2026-06-27
- **Status:** Approved design; pending implementation
- **Related:** `docs/conventions.md` (coding standards, signals-vs-calls),
  `docs/feel-reference.md` (frame counting), `docs/fsm.md` (team-facing state
  catalog — produced during implementation)

This is the **decision record + API contract** for the hand-rolled state machine
every character uses. It is sized so others can execute against it without
re-deriving the architecture (the plan's "one person specs, others implement"
workflow for Phase 1).

---

## 1. Goal

Deliver the FSM *skeleton, rules, and state vocabulary* that all later movement
(1.4), block/collision (1.5), and combat (Phase 2) plug into. A character's
"what am I allowed to do right now" lives here; "what I actually do" lives in the
character controller built on top.

## 2. Non-goals (explicitly out of 1.3)

To keep this data-light and avoid pre-empting later design:

- **No movement physics** — velocities, jump arcs, dash distances are 1.4.
- **No collision / pushboxes / block detection** — 1.5.
- **No frame-data / hit-resolution** — Phase 2. The FSM never reads a move's
  startup/active/recovery; it only knows *which state* you're in.
- **No cancel/timing rules** — "are attacks interruptible," cancel windows, juggle
  gravity are the cancel system (3.5) layered on later. The FSM enforces only
  *structural* legality, never *timing* legality.
- **No generic FSM framework, no ECS, no per-state class hierarchy** — one small
  enum-based machine (per `conventions.md` "don't over-engineer").

## 3. Architecture

### 3.1 A dependency-free module

`CharacterStateMachine` is a `RefCounted` (no `Node`, no scene, no input, no
physics). This makes it the smallest independently testable unit and lets the
Phase-1 "parallel trio" (1.1 overlay, 1.2 input, 1.3 FSM) proceed without
blocking each other.

### 3.2 Controller owns it and polls it

The character controller (1.4) holds one `CharacterStateMachine` and, each
`_physics_process` frame, **reads `state` / `frame_in_state` and acts** via a
`match`. Per `conventions.md`: anything whose timing affects the match is polled
or called directly — never routed through a signal.

```
FSM      = "what state am I in + which transitions are structurally legal"
Controller = "given my state and frame_in_state, what do I do this frame"
```

### 3.3 Signal is cosmetic only

`state_changed(from, to)` exists solely for decoupled reflectors that *show*
state but never change the match outcome — the debug label now; VFX/SFX later.
This is the conventions doc's signal-vs-call test applied exactly.

## 4. The State enum

20 states, faithful to the `game.md` 1.3 list, nested as
`CharacterStateMachine.State`:

```gdscript
enum State {
    IDLE, WALK_F, WALK_B, CROUCH,
    JUMP_START, JUMP_AIR, JUMP_F, JUMP_B, JUMP_LAND,
    DASH, BACKDASH, BLOCK,
    FAST_ATTACK, HEAVY_ATTACK, SKILL,
    HITSTUN, BLOCKSTUN, KNOCKDOWN, GETUP, KO,
}
```

**Locked interpretations** (documented in `fsm.md`):

- **Jump phases:** `JUMP_START` = prejump squat (grounded, committed) →
  takeoff into exactly one airborne state — `JUMP_AIR` (neutral), `JUMP_F`
  (forward), or `JUMP_B` (back), chosen by held direction at takeoff →
  `JUMP_LAND` = landing recovery (grounded, committed) → resolves to `IDLE`.
  The three airborne states are mutually exclusive; they differ later only in
  horizontal velocity (1.4) and air options.
- **`BLOCK`** is a single state for 1.3. High/low block is a later refinement
  (5.1 lists "block hi/lo" animations); not modeled as separate states yet.
- **`BLOCKSTUN` vs `BLOCK`:** `BLOCK` is the chosen guard stance; `BLOCKSTUN` is
  the forced freeze after guarding a hit.

## 5. State categories (the "data-light rules")

Transitions are decided by **category**, not a 20×20 matrix. Categories are
`static` predicates over a `State`:

| Helper | True for | Meaning |
|---|---|---|
| `is_grounded(s)` | IDLE, WALK_F/B, CROUCH, JUMP_START, JUMP_LAND, DASH, BACKDASH, BLOCK, FAST/HEAVY/SKILL\*, HITSTUN\*, BLOCKSTUN, KNOCKDOWN, GETUP | on the floor |
| `is_airborne(s)` | JUMP_AIR, JUMP_F, JUMP_B | in the air |
| `is_actionable(s)` | IDLE, WALK_F, WALK_B, CROUCH, BLOCK | may begin a new ground action |
| `is_attacking(s)` | FAST_ATTACK, HEAVY_ATTACK, SKILL | in an attack |
| `is_in_reaction(s)` | HITSTUN, BLOCKSTUN, KNOCKDOWN | reacting to being hit/blocking |
| `is_busy(s)` | JUMP_START, JUMP_LAND, DASH, BACKDASH, FAST/HEAVY/SKILL, GETUP | committed; runs to completion |
| `is_ko(s)` | KO | terminal |

\* In 1.3, attacks and `HITSTUN` are treated as **grounded** (`is_airborne`
returns true only for `JUMP_AIR/F/B`). Air normals and air hits don't exist until
Phase 2/3; the air variants — and an attack/hitstun air-vs-ground distinction —
are added then. 1.3 needs only the ground reading to enforce legality.

## 6. Transition rules (structural legality only)

`can_transition(to)` returns whether a **player/logic-initiated** move from the
current `state` to `to` is structurally legal. It is defined as an explicit set
of allowed exits **per source category** — there is no 20×20 matrix:

| From (current `state`) | May `request` → |
|---|---|
| `KO` | *nothing* (only `reset()` leaves KO) |
| `is_actionable` — IDLE, WALK_F, WALK_B, CROUCH, BLOCK | IDLE, WALK_F, WALK_B, CROUCH, BLOCK, JUMP_START, DASH, BACKDASH, FAST_ATTACK, HEAVY_ATTACK, SKILL |
| `is_airborne` — JUMP_AIR, JUMP_F, JUMP_B | JUMP_LAND |
| JUMP_START | JUMP_AIR, JUMP_F, JUMP_B *(takeoff)* |
| JUMP_LAND / DASH / BACKDASH / GETUP | IDLE |
| FAST_ATTACK / HEAVY_ATTACK / SKILL | IDLE *(recovery done)* |
| HITSTUN | IDLE |
| BLOCKSTUN | IDLE |
| KNOCKDOWN | GETUP |

Key consequences this encodes:

- **Air↔ground boundary:** grounded reaches air **only** via `JUMP_START`;
  airborne reaches ground **only** via `JUMP_LAND`. No direct crossing.
- **Busy states allow only their own exit** — a new action (e.g.
  `DASH → HEAVY_ATTACK`) is rejected in 1.3. Attack→attack/special **cancels**
  are 3.5: opened later by the controller checking frame windows before it calls
  `request`, not by widening this table.
- **Knockdown wakeup** is `KNOCKDOWN → GETUP → IDLE`; `KNOCKDOWN → IDLE` direct
  is rejected.
- **Reactions are entered by `force`, never `request`** (see §7); the rows above
  describe only how you *leave* them.

`request(next)` applies the change iff `can_transition(next)`, fires
`state_changed`, and returns the bool.

## 7. Forced / interrupt transitions

Being hit interrupts almost anything. These bypass the §6 request rules:

- `force(next)` performs the transition if `next` is a legal *forced* target
  (`HITSTUN`, `BLOCKSTUN`, `KNOCKDOWN`, or `KO`) and the current state is **not**
  `KO`. `assert`s otherwise (developer invariant). `GETUP` is **not** forced — it
  is `request`ed out of `KNOCKDOWN` (§6).
- Convenience entry points the controller/combat layer calls:
  `on_hit()` → `force(HITSTUN)`, `on_launched()` → `force(KNOCKDOWN)`,
  `on_blocked()` → `force(BLOCKSTUN)`, `on_ko()` → `force(KO)`.
- `force` from any non-KO state is legal (you can be hit out of startup, jump,
  block, etc.). KO is the only thing it can't override.

## 8. Frame counter contract

`frame_in_state` is the determinism-critical part downstream code reads to know
"how long have I been in this state" (e.g. "prejump is 4 frames").

- **`frame_in_state == 0` on the entry frame.** Any successful
  `request`/`force`/`reset` sets `frame_in_state = 0` and an internal
  `_entered_this_frame` flag, and updates `prev_state`.
- The controller calls **`tick()` once per physics frame, at the end of its
  update.** `tick()` increments `frame_in_state` *unless* `_entered_this_frame`
  is set, then clears that flag. Net effect: a state entered this frame reads `0`
  for the remainder of the frame and begins counting `1, 2, …` on subsequent
  frames — including states entered mid-frame.
- All counting is integer frames at 60 Hz (`conventions.md` — never `delta`).

## 9. Public API surface

```gdscript
class_name CharacterStateMachine
extends RefCounted

enum State { ... }                       # §4

signal state_changed(from: State, to: State)   # cosmetic reflectors only

var state: State                          # current; treat as read-only externally
var prev_state: State
var frame_in_state: int                   # §8

func request(next: State) -> bool         # player/logic transition; gated by can_transition
func force(next: State) -> void           # reaction/interrupt; §7
func reset(to: State = State.IDLE) -> void  # round reset; only legal exit from KO
func tick() -> void                       # once per physics frame, end of update; §8
func can_transition(to: State) -> bool    # structural legality from current state

static func is_grounded(s: State) -> bool
static func is_airborne(s: State) -> bool
static func is_actionable(s: State) -> bool
static func is_attacking(s: State) -> bool
static func is_in_reaction(s: State) -> bool
static func is_busy(s: State) -> bool
static func is_ko(s: State) -> bool
```

## 10. Verification

1. **Test-first, headless** — `tests/test_fsm.gd`, run with `godot --headless`.
   Asserts (written before the implementation, must fail first):
   - fresh machine starts `IDLE`, `frame_in_state == 0`;
   - `KO` is terminal: `request`/`force` to anything fails/asserts; `reset()`
     escapes it;
   - airborne → grounded neutral is rejected; grounded → `JUMP_AIR` direct is
     rejected; `IDLE → JUMP_START → JUMP_AIR → JUMP_LAND → IDLE` all pass;
   - a busy state allows only its exit: `DASH → IDLE` passes, `DASH → HEAVY_ATTACK`
     is rejected;
   - `force(HITSTUN)` succeeds from a sample of non-KO states; fails from `KO`;
   - `KNOCKDOWN → GETUP → IDLE` passes; `KNOCKDOWN → IDLE` direct rejected;
   - frame-counter contract (§8): entry frame `0`, `tick()` → `1`, change
     mid-sequence resets to `0`, no double-count on the entry frame;
   - `request` returns `true` on legal / `false` on illegal.
2. **Throwaway visual demo** — `scenes/dev/fsm_demo.tscn` + `scripts/dev/fsm_demo.gd`:
   one box, an on-screen `Label` showing `state | frame_in_state | prev`, keyboard
   mapped to `request()` (move/jump/crouch/attack/block) and one key calling
   `force(HITSTUN)`. Run through the **Godot MCP** (`run_project` →
   `get_debug_output`) to confirm it ticks and transitions live. **Clearly marked
   1.3-local throwaway** — replaced by the real 1.1 debug overlay + 1.2 input
   during 1.4 integration.

## 11. Deliverables

| File | Role |
|---|---|
| `scripts/fsm/character_state_machine.gd` | the FSM (enum + helpers + machine) — the real artifact |
| `tests/test_fsm.gd` | headless tests (new `tests/` dir; `conventions.md` already defines a `test` commit type) |
| `scenes/dev/fsm_demo.tscn` + `scripts/dev/fsm_demo.gd` | throwaway visual proof |
| `docs/fsm.md` | **required team deliverable**: state catalog, transition diagram, frame contract, how a controller consumes the FSM |

## 12. Notes for downstream phases

- **1.4** consumes `state`/`frame_in_state` in `_physics_process`; it owns the
  `match` that maps state → movement, and decides when busy states complete
  (then calls `request(IDLE)` / airborne).
- **1.5** adds `BLOCK` entry conditions and uses `is_in_reaction` for
  hit/guard handling; pushboxes are independent of the FSM.
- **Phase 2** adds frame-data; attacks set their own state durations by reading
  `frame_in_state` against a move's startup/active/recovery. The FSM stays
  duration-agnostic.
- **3.5 cancels** open attack→attack/attack→special transitions by the
  controller checking frame windows before `request` — no FSM change needed.
- **6.4 grappler (Jacob)** may add `GRAB_ATTEMPT`, `GRABBED`, `THROW_RELEASE`,
  tech-escape states. The enum + category model extends cleanly: add the members,
  slot them into the right category predicates, add their transition rules.
