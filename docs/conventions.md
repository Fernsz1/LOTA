# Conventions

Shared standards for the Shadow Fighter (LOTA) project. Point every Claude/Codex
session at this file instead of re-explaining context.

> Sections marked **(Phase 0.4)** are stubs to be filled in during task 0.4
> (coding standards, naming, frame-data authoring). Branch/commit/repo
> conventions below are authored in 0.1.

---

## Repository layout

| Folder | Holds |
|---|---|
| `/scenes` | Godot scenes (`.tscn`). |
| `/scripts` | GDScript (`.gd`) not owned by a single character. |
| `/characters` | Per-character bundles (states, move lists, stats). |
| `/art` | Source + exported art (LibreSprite files, spritesheets). |
| `/data` | Frame-data resources (`.tres`) and other game data. |
| `/docs` | Shared design/reference docs (this file, art-pipeline, fsm, etc.). |

Empty folders are kept in git via a `.gitkeep` file. Delete the `.gitkeep`
once a folder has real tracked content.

## Asset / binary handling — **no Git LFS (for now)**

We are **not** using Git LFS in v1. Our art is all-black silhouette PNG
spritesheets — small enough that plain git handles them fine, and LFS adds
setup friction (every contributor must install `git-lfs`; clones/CI get more
complex). 

Revisit only if `/art` genuinely balloons (e.g. many large `.ase`/`.aseprite`
source files or high-res sheets). If we ever do adopt it, track patterns like
`*.aseprite`, `*.png` under `/art` via `.gitattributes` — but not before it's
an actual problem.

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

## Coding standards **(Phase 0.4 — TODO)**

GDScript naming, file naming, indentation, signal vs. direct-call conventions.

## How frame data is authored **(Phase 0.4 — TODO)**

Agree before Phase 2 needs it. The data layer is authoritative; animation
syncs on top. See the frame-data resource format (Phase 2.2) once it exists.
