extends CanvasLayer
## Match HUD (2.6): a gritty cel-shaded combat overlay — portrait plates, fighter
## names, archetype chips, health bars, SIGABO super meters, a round timer, round
## pips, and an announce line. Cosmetic only: MatchManager pushes values in; this
## never reads or writes game state. Value tweening is a rendering-only concern.

const TIMER_WARN: int = 10
const TIMER_OK := Color(1, 0.831, 0, 1)        # #ffd400
const TIMER_LOW := Color(1, 0.231, 0.231, 1)   # #ff3b3b
const PIP_OFF := Color(0.149, 0.149, 0.18, 1)  # #26262e
const ACCENT_DEFAULT := {1: Color(0.165, 0.659, 1, 1), 2: Color(1, 0.231, 0.231, 1)}

const METER_FILL := {
	1: preload("res://assets/hud/meter_fill_blue.png"),
	2: preload("res://assets/hud/meter_fill_red.png"),
}
const METER_FILL_READY := preload("res://assets/hud/meter_fill_green.png")

const DRAIN_TIME: float = 0.35
const FLASH_TIME: float = 0.17

@onready var _health := {1: $HUD/P1/Health, 2: $HUD/P2/Health}
@onready var _flash := {1: $HUD/P1/Health/Flash, 2: $HUD/P2/Health/Flash}
@onready var _meter := {1: $HUD/P1/MeterRow/Meter, 2: $HUD/P2/MeterRow/Meter}
@onready var _super_ready := {1: $HUD/P1/MeterRow/Ready, 2: $HUD/P2/MeterRow/Ready}
@onready var _name := {1: $HUD/P1/Name, 2: $HUD/P2/Name}
@onready var _pips := {
	1: [$HUD/P1/Pips/Pip0, $HUD/P1/Pips/Pip1],
	2: [$HUD/P2/Pips/Pip0, $HUD/P2/Pips/Pip1],
}
@onready var _timer: Label = $HUD/Center/TimerPlate/Timer
@onready var _round: Label = $HUD/Center/Round
@onready var _announce: Label = $HUD/Center/Announce

var _accent := {1: ACCENT_DEFAULT[1], 2: ACCENT_DEFAULT[2]}
var _hp_target := {1: 1.0, 2: 1.0}
var _meter_target := {1: 0.0, 2: 0.0}

func set_health(player: int, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	_hp_target[player] = f
	_health[player].value = f * 100.0

func set_meter(player: int, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	_meter_target[player] = f
	_meter[player].value = f * 100.0
	var ready: bool = f >= 1.0
	_meter[player].texture_progress = METER_FILL_READY if ready else METER_FILL[player]
	_super_ready[player].visible = ready

func set_timer(seconds: int) -> void:
	_timer.text = "%02d" % seconds
	_timer.label_settings.font_color = TIMER_LOW if seconds <= TIMER_WARN else TIMER_OK

func set_rounds(player: int, won: int) -> void:
	var pips: Array = _pips[player]
	for i in pips.size():
		pips[i].color = _accent[player] if i < won else PIP_OFF

func set_fighter(player: int, fighter_name: String, color: Color) -> void:
	_accent[player] = color
	_name[player].text = fighter_name
	_name[player].label_settings.font_color = color

func announce(text: String) -> void:
	_announce.text = text

func snap() -> void:
	for p in [1, 2]:
		_health[p].value = _hp_target[p] * 100.0
		_meter[p].value = _meter_target[p] * 100.0
