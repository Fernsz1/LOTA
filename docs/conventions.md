# Conventions

Shared standards for the Shadow Fighter (LOTA) project. Point every Claude/Codex
session at this file instead of re-explaining context.

> Branch / commit / repo conventions were authored in 0.1; coding standards and
> frame-data authoring in 0.4. Two open decisions await team sign-off before 2.2
> — see the end of "How frame data is authored".

---

## Repository layout

| Folder | Holds |
|---|---|
| `/scenes` | Godot scenes (`.tscn`). |
| `/scripts` | GDScript (`.gd`) not owned by a single character. |
| `/characters` | Per-character bundles (states, move lists, stats). |
| `/art` | Source character art (PNG limb/part images) and Skeleton2D rig assets. |
| `/data` | Frame-data resources (`.tres`) and other game data. |
| `/docs` | Shared design/reference docs (this file, art-pipeline, fsm, etc.). |

Empty folders are kept in git via a `.gitkeep` file. Delete the `.gitkeep`
once a folder has real tracked content.

## Asset / binary handling — **no Git LFS (for now)**

We are **not** using Git LFS in v1. Our art is all-black silhouette PNG
part images (limbs/body pieces) assembled into Godot Skeleton2D rigs — small
enough that plain git handles them fine, and LFS adds setup friction (every
contributor must install `git-lfs`; clones/CI get more complex).

Revisit only if `/art` genuinely balloons (e.g. many large high-res part
images or source files). If we ever do adopt it, track patterns like `*.png`
under `/art` via `.gitattributes` — but not before it's an actual problem.

## Branching

- `main` — always runnable. Protected in spirit: never commit broken builds here.
- `dev` — integration branch for in-progress work.
- Feature branches off `dev` (or `main` if no `dev` cycle is active), named:
  - `feat/<phase>-<short-desc>` — e.g. `feat/1.3-fsm-architecture`
  - `fix/<short-desc>`
  - `docs/<short-desc>`
  - `spike/<short-desc>` — throwaway experiments (Phase 0 spikes).
- One person owns one subphase/branch at a time (per the plan's parallelization
  notes) to avoid divergent architectures.

## Commits — [Conventional Commits](https://www.conventionalcommits.org/)

Format: `type(scope): description [task]`

```
feat(input): add ring buffer for motion inputs [1.2]
```

- **Subject**: imperative mood, present tense, lowercase, no trailing period.
  "add input ring buffer", not "Added input ring buffer.".
- **type** (required), one of:
  - `feat` — a new feature/gameplay capability
  - `fix` — a bug fix
  - `docs` — docs only (e.g. this file, `/docs`)
  - `refactor` — code change that neither fixes a bug nor adds a feature
  - `perf` — performance improvement
  - `test` — adding/adjusting tests
  - `spike` — throwaway experiment (Phase 0 spikes)
  - `chore` — tooling, project setup, deps, housekeeping
- **scope** (optional but encouraged): the area touched — `input`, `fsm`,
  `combat`, `jerb`, `rainne`, `setup`, `ci`, etc.
- **task**: append the plan task number when it applies, e.g. `[1.2]`.
- **Body** (optional): bullet points explaining *what* and *why*, wrapped ~72 cols.
- **Breaking changes**: add `!` after type/scope (`feat(fsm)!: ...`) and/or a
  `BREAKING CHANGE:` footer.
- Keep commits focused; a commit should build and run.

## Pull / merge flow

- Merge feature branches into `dev`; promote `dev` → `main` at stable points.
- Respect the plan's gates (e.g. nothing in Phase 5 art before 3.6 GO/NO-GO
  passes). Don't merge work that jumps a gate.

---

## Coding standards

Baseline: **GDScript on Godot 4.7**, following the official GDScript style guide.
This section records our defaults and the deviations that matter for a
deterministic fighter. When in doubt, **match the surrounding code.**

### Naming

| Thing | Convention | Example |
|---|---|---|
| Script / file | `snake_case.gd` | `attack_state.gd` |
| Scene file | `snake_case.tscn` | `training_mode.tscn` |
| Resource file | `snake_case.tres` | `cr_mk.tres` |
| Class (`class_name`) | `PascalCase` | `class_name MoveData` |
| Node (in tree) | `PascalCase` | `HurtboxRoot` |
| Function / method | `snake_case()` | `apply_hitstop()` |
| Variable | `snake_case` | `frame_count` |
| Private member (internal) | `_leading_underscore` | `_buffer_index` |
| Constant | `CONSTANT_CASE` | `MAX_HEALTH` |
| Enum (type / members) | `PascalCase` / `CONSTANT_CASE` | `State.HITSTUN` |
| Signal | `snake_case`, past-tense event | `hit_landed`, `round_ended` |
| Boolean | `is_` / `has_` / `can_` prefix | `is_airborne` |

### Layout & formatting

- **Tabs** for indentation (Godot's default and style-guide standard). One
  statement per line; ~100-column soft wrap.
- **Static typing everywhere it's cheap** (`var x: int`, `func f() -> void`).
  Catches errors at parse time, documents intent, runs faster.
- One primary `class_name` per file; the file name matches the class in
  `snake_case`.
- Character-owned scripts live under `/characters/<name>/`; cross-character code
  under `/scripts` (see repo layout above).

### Frames are the unit (determinism)

The fighter is deterministic *because* it steps on a fixed clock. Protect that:

- **All combat timing is integer frames at 60 Hz — never seconds, never
  `delta`.** A move is "12 frames", not "0.2s".
- **Gameplay runs in `_physics_process`**, not `_process`. Never scale combat
  values by `delta`.
- **No unseeded randomness in combat.** If a move ever needs RNG, draw from one
  seeded, frame-synced generator so a match is reproducible.
- Rendering-only concerns (camera smoothing, cosmetic interpolation) may use
  `_process`/`delta` — they must never feed back into game state.

### Signals vs. direct calls

The rule that keeps combat deterministic and debuggable:

- **Direct calls (or per-frame polling) for anything whose timing affects the
  match:** hit/hurtbox checks, FSM transitions, frame-data application, damage,
  hitstop. Explicit call order = reproducible order (same reasoning as choosing
  manual AABB over `Area2D` signals in 2.1: less code, more correct).
- **Signals for decoupled, fire-and-forget consumers that only *reflect* state:**
  health-bar updates, SFX/VFX triggers, round start/end, menu events.
- **Test:** *if a listener's timing could change who wins the exchange, call it
  directly; if it only shows the player what already happened, signal it.*

### Code philosophy (don't over-engineer)

Echoes the plan's "what we are deliberately NOT doing." Bias to the smallest
thing that works:

- **Minimum code that solves the problem.** No speculative abstractions, no
  configurability nobody asked for, no error handling for impossible states. No
  ECS, no generic FSM framework, no custom data editor — all explicitly out.
- **Surgical changes.** Touch only what the task needs; match existing style;
  don't refactor what isn't broken. Remove only the orphans your change creates.
- **Surface assumptions, don't bury them.** When a choice is ambiguous, record it
  in the relevant `/docs` file (or flag it) instead of silently picking.
- **Define "done" verifiably.** A move is correct when the training-mode readout
  (4.2) matches its `.tres` — a checkable criterion beats "looks right".
- **Data over hard-coding.** Anything a designer tunes (frames, damage, speeds)
  lives in a `.tres`, not a magic number in code.
- `assert()` developer-invariants (e.g. a move has ≥1 active frame); don't branch
  defensively for states that can't occur.
- Comments explain **why**, not what.

## How frame data is authored

> **The data layer is authoritative; animation syncs on top.** The number hits,
> not the drawing. If a `.tres` and its animation disagree, the `.tres` wins and
> the animation gets re-timed (the 5.4 reconciliation job). This is what lets us
> validate feel on placeholder boxes before any art exists. See
> `feel-reference.md` §2.

This section fixes the **conventions** (units, naming, ownership, location). The
authoritative resource class/schema is defined in **2.2** — agreeing the
conventions now keeps 2.2 from churning.

### Format & tooling (locked)

- A move is a **Godot Resource saved as `.tres`**, authored and edited in the
  **Godot inspector**. Native, text-based, diffable, parseable.
- **We do NOT** build a custom data format, an external editor, or a
  spreadsheet-of-record. Hand-editing the text `.tres` is fine (diff-friendly);
  the inspector is preferred (typed + validated).
- **One move = one `.tres`.**

### Units & frame convention

- **Integer frames at 60 Hz.** No seconds or milliseconds in the data.
- Reuse the single counting convention from `feel-reference.md` §3 — don't
  redefine it:
  - `startup`, `active`, `recovery` are **three disjoint counts**; first active
    frame = `startup + 1`; total = `startup + active + recovery`.
  - External frame data (Dustloop / SuperCombo) counts first-active as startup,
    so **subtract 1** when importing.

### Fields (conventions; final schema in 2.2)

Names/units the 2.2 `Move` resource should use, mirroring the plan's 2.2 list:

| Field | Unit / type | Note |
|---|---|---|
| `startup` / `active` / `recovery` | frames (int) | disjoint; see above |
| `hitboxes` | `Rect2` set per active frame | local space; manual AABB (2.1) |
| `damage` | int | |
| `hitstun` / `blockstun` | frames (int) | hitstun > blockstun |
| `pushback_hit` / `pushback_block` | px/frame or impulse | block ≥ hit |
| `hitstop` | frames (int) | applied *before* hitstun |
| `on_block` | frames (int) | **store or derive?** — see open decisions |

### Naming & location

- File: `snake_case.tres`, named by the move — `jab.tres`, `cr_mk.tres`,
  `fireball.tres`. Keep names consistent with feel-reference notation where one
  exists.
- **Location (to ratify):** per-character moves under
  `/characters/<name>/moves/`, keeping a character's bundle self-contained;
  `/data` for cross-character/system resources. *This refines the `/data`
  repo-layout row — confirm before 2.2 builds it.*

### Ownership & validation

- The `.tres` is the **single source of truth** for timing/damage. Animation
  frame counts reconcile *to* it (5.4), never the reverse.
- Validate on load with `assert()`: counts ≥ 0, `active` ≥ 1, a hitbox present on
  each frame that should have one.
- **Training mode (4.2) is the verification surface** — its live readout must
  match the `.tres`. If they differ, the code/animation is wrong, not the data.

### Open decisions to ratify (before 2.2)

1. **Move-file location** — `/characters/<name>/moves/` (recommended,
   self-contained) vs a flat `/data/moves/`. Affects how characters bundle (3.1).
2. **`on_block` stored vs derived** — recommend **derive** for display via
   `blockstun − ((active − 1) + recovery)` (feel-reference §3) to prevent desync;
   store only for hand-tuned exceptions.
