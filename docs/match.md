# Round & Match (2.6)

How a round is won and a best-of-3 match runs. Companion docs: `combat.md` (how hits
resolve), `feel-reference.md` (frame vocabulary), `fsm.md` (states). Frames are integer
@60 Hz.

The split mirrors the rest of the codebase: **pure progression logic** in a
`RefCounted` (unit-tested headless) and **thin Node orchestration** that touches the
scene + HUD.

## `MatchState` (pure — `scripts/match/match_state.gd`)

Tracks only the rules: `p1_rounds` / `p2_rounds`, `time_left` (frames), and `phase`
(`FIGHT` / `ROUND_END` / `MATCH_END`).

- `ROUNDS_TO_WIN = 2` (best-of-3), `ROUND_FRAMES = 99 * 60` (99-second round).
- `start_match()` / `start_round()`, `tick_timer()` (clamps at 0) / `time_up()` / `seconds_left()`.
- `record_round_win(player)` — `player` 1/2 awards a point and sets `MATCH_END` if it
  clinches the match else `ROUND_END`; `player == 0` is a **draw** (no point → `ROUND_END`, replay).
- `is_match_over()` / `match_winner()`.

Unit tests: `tests/test_match_state.gd`.

## `MatchManager` (node — `scripts/match/match_manager.gd`)

A plain `Node` in `main.tscn` at `process_physics_priority = 2`, so it reads
**post-resolution** health each frame (after `main.gd` applied this frame's hits). Holds
NodePaths to P1, P2, and the HUD.

- **FIGHT**: update health bars; while either fighter `is_frozen()` (hitstop) it pauses
  (no timer tick, no win check). Otherwise `tick_timer()` and check `_winner_now()`:
  a fighter at `health <= 0` loses; on timeout the higher-HP fighter wins (equal → draw).
- **Round end**: `force_ko()` the loser(s) (→ `KO` state, which is invulnerable),
  `record_round_win`, update the round pips, announce `K.O.` / `DRAW` / `PLAYER N WINS`,
  then hold `RESET_DELAY = 90` frames.
- **Reset**: `CharacterController.reset_for_round(spawn_x)` restores position
  (`P1_SPAWN_X = 400`, `P2_SPAWN_X = 880`), `health = MAX_HEALTH`, clears velocity /
  hitstop / stun / pushback / current move, and `FSM.reset(IDLE)`. Then `start_round()`.
- **MATCH_END**: hold the result until `ui_accept` → `start_match()` (rematch).

## HUD (`scenes/match_hud.tscn` + `scripts/match_hud.gd`)

A cosmetic `CanvasLayer` (separate from the dev `debug_overlay`): two health bars
(P1 depletes from the inner edge, P2 mirrors), a centered round timer, per-player round
pips, and a centered announce line. The MatchManager pushes values in via
`set_health / set_timer / set_rounds / announce`; the HUD never reads game state.

## Verifying

- **Unit (headless):** `<godot> --headless --script res://tests/test_match_state.gd`.
- **Live:** a throwaway combat demo (drives P1 into a dummy via the real input path) was
  run via the Godot MCP and confirmed the full chain — heavy hit → damage/hitstop/pushback
  → knockdown → getup → health to 0 → **KO → round point → reset** (and, with the dummy
  holding back, **BLOCKSTUN with no damage**). Removed after verification, as the 1.3 FSM
  demo was.
