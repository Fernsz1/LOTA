class_name MatchState
extends RefCounted
## Pure round/match progression (2.6). No Node, no rendering — tracks rounds won, the
## round timer, and the match phase. The MatchManager node drives it (ticks the timer,
## feeds round winners) and reflects it to the HUD; KO/health live on the controllers.
## Pure logic → unit-testable headless.

const ROUNDS_TO_WIN: int = 2          # best-of-3
const ROUND_FRAMES: int = 99 * 60     # 99-second round at 60 Hz

enum Phase { FIGHT, ROUND_END, MATCH_END }

var p1_rounds: int = 0
var p2_rounds: int = 0
var time_left: int = ROUND_FRAMES
var phase: int = Phase.FIGHT

## Begin (or restart) a round: full timer, back to FIGHT.
func start_round() -> void:
	time_left = ROUND_FRAMES
	phase = Phase.FIGHT

## Hard reset for a brand-new match.
func start_match() -> void:
	p1_rounds = 0
	p2_rounds = 0
	start_round()

## Advance the round clock one frame (clamped at 0). Only meaningful while FIGHT.
func tick_timer() -> void:
	if time_left > 0:
		time_left -= 1

func time_up() -> bool:
	return time_left <= 0

## Seconds remaining, rounded up — for the HUD.
func seconds_left() -> int:
	return (time_left + 59) / 60

## Record a round win for player 1 or 2. Moves to MATCH_END if it clinches the match,
## otherwise ROUND_END. A winner of 0 means a draw (no point) → ROUND_END (replay).
func record_round_win(player: int) -> void:
	if player == 1:
		p1_rounds += 1
	elif player == 2:
		p2_rounds += 1
	phase = Phase.MATCH_END if is_match_over() else Phase.ROUND_END

func is_match_over() -> bool:
	return p1_rounds >= ROUNDS_TO_WIN or p2_rounds >= ROUNDS_TO_WIN

## Match winner (1/2), or 0 if undecided.
func match_winner() -> int:
	if p1_rounds >= ROUNDS_TO_WIN:
		return 1
	if p2_rounds >= ROUNDS_TO_WIN:
		return 2
	return 0
