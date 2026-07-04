extends CanvasLayer
## Match HUD (2.6): two health bars, a round timer, per-player round pips, and a
## centered announce line. Cosmetic only — the MatchManager pushes values in; this
## never reads or writes game state.

const BAR_W: float = 480.0   # must match the bar ColorRect widths in match_hud.tscn
const METER_CHARGE_COLOR: Color = Color(0.55, 0.45, 0.15, 1)   # dim gold while filling
const METER_READY_COLOR: Color = Color(1, 0.85, 0.2, 1)        # bright gold at full (matches round pips)

@onready var _p1_fill: ColorRect = $P1Bar/Fill
@onready var _p2_fill: ColorRect = $P2Bar/Fill
@onready var _p1_meter_fill: ColorRect = $P1Meter/Fill
@onready var _p2_meter_fill: ColorRect = $P2Meter/Fill
@onready var _timer: Label = $Timer
@onready var _round_labels: Array[Label] = [$P1Rounds, $P2Rounds]
@onready var _announce: Label = $Announce

## frac in 0..1. P1 depletes from the inner (right) edge; P2 mirrors (inner/left edge).
func set_health(player: int, frac: float) -> void:
	var w: float = BAR_W * clampf(frac, 0.0, 1.0)
	if player == 1:
		_p1_fill.size.x = w
	else:
		_p2_fill.size.x = w
		_p2_fill.position.x = BAR_W - w

## frac in 0..1. Fill directions mirror the health bars; the fill brightens at
## full so "ultimate ready" reads at a glance.
func set_meter(player: int, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	var w: float = BAR_W * f
	var fill: ColorRect = _p1_meter_fill if player == 1 else _p2_meter_fill
	fill.color = METER_READY_COLOR if f >= 1.0 else METER_CHARGE_COLOR
	fill.size.x = w
	if player == 2:
		fill.position.x = BAR_W - w

func set_timer(seconds: int) -> void:
	_timer.text = str(seconds)

func set_rounds(player: int, won: int) -> void:
	_round_labels[player - 1].text = "●".repeat(won)

func announce(text: String) -> void:
	_announce.text = text
