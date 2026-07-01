class_name TrainingHUD
extends CanvasLayer
## 4.1/4.2 — Training mode HUD.
## Health bars (4.1), frame advantage on hit/block, and live move readout (4.2).

const BAR_W: float = 480.0
const ADVANTAGE_DISPLAY_TIME: float = 3.0   # seconds before advantage label clears

@onready var _p1_fill: ColorRect = $P1Bar/Fill
@onready var _p1d_fill: ColorRect = $P1DummyBar/Fill
@onready var _p2d_fill: ColorRect = $P2DummyBar/Fill
@onready var _p2_fill: ColorRect = $P2Bar/Fill
@onready var _p1_info: Label = $P1Info
@onready var _p1_dummy_info: Label = $P1DummyInfo
@onready var _p2_dummy_info: Label = $P2DummyInfo
@onready var _p2_info: Label = $P2Info
@onready var _p1_move_lbl: Label = $P1MoveReadout
@onready var _p2_move_lbl: Label = $P2MoveReadout
@onready var _p1_adv_lbl: Label = $P1Advantage
@onready var _p2_adv_lbl: Label = $P2Advantage

var _p1_adv_timer: float = 0.0
var _p2_adv_timer: float = 0.0


## idx: 1=P1, 2=P1Dummy, 3=P2Dummy, 4=P2.
func set_health(idx: int, frac: float) -> void:
	var w: float = BAR_W * clampf(frac, 0.0, 1.0)
	match idx:
		1:
			_p1_fill.size.x = w
		2:
			_p1d_fill.size.x = w
		3:
			_p2d_fill.size.x = w
			_p2d_fill.position.x = BAR_W - w
		4:
			_p2_fill.size.x = w
			_p2_fill.position.x = BAR_W - w


func set_player_info(player_idx: int, infinite: bool) -> void:
	var text: String = "P%d: %s" % [player_idx, "♥INF" if infinite else ""]
	if player_idx == 1:
		_p1_info.text = text
	else:
		_p2_info.text = text


func set_dummy_info(dummy_idx: int, mode_label: String, infinite: bool) -> void:
	var inf: String = "  ♥INF" if infinite else ""
	if dummy_idx == 1:
		_p1_dummy_info.text = "P1Dummy: %s%s" % [mode_label, inf]
	else:
		_p2_dummy_info.text = "P2Dummy: %s%s" % [mode_label, inf]


## 4.2 — Live move readout: shows move name, frame data, and current phase.
## side: 1=P1 (left), 2=P2 (right). move may be null when no attack is active.
func set_move_readout(side: int, move: MoveData, fis: int) -> void:
	var lbl: Label = _p1_move_lbl if side == 1 else _p2_move_lbl
	if move == null:
		lbl.text = ""
		return
	var name_str: String = move.move_name if move.move_name != "" else "MOVE"
	var data_str: String = "S:%d A:%d R:%d" % [move.startup, move.active, move.recovery]
	var phase_str: String
	var col: Color
	if fis < move.startup:
		phase_str = "STARTUP [%d]" % (move.startup - fis)
		col = Color(0.85, 0.85, 0.85, 1)      # white — waiting to hit
	elif fis < move.startup + move.active:
		phase_str = "ACTIVE [%d]" % (move.startup + move.active - fis)
		col = Color(0.3, 0.95, 0.4, 1)        # green — hitbox live
	else:
		phase_str = "RECOVERY [%d]" % (move.total() - fis)
		col = Color(0.95, 0.45, 0.3, 1)       # red-orange — vulnerable
	lbl.text = "%s  %s  %s" % [name_str, data_str, phase_str]
	lbl.add_theme_color_override("font_color", col)


## 4.2 — Show frame advantage after a hit or block. Positive = attacker advantage.
## Clears automatically after ADVANTAGE_DISPLAY_TIME seconds.
func show_advantage(side: int, adv: int) -> void:
	var lbl: Label = _p1_adv_lbl if side == 1 else _p2_adv_lbl
	var sign_str: String = "+" if adv > 0 else ""
	lbl.text = "adv: %s%d" % [sign_str, adv]
	var col: Color
	if adv > 0:
		col = Color(0.3, 0.9, 0.35, 1)        # green — attacker acts first
	elif adv < 0:
		col = Color(0.95, 0.3, 0.3, 1)        # red — attacker is punishable
	else:
		col = Color(0.85, 0.85, 0.85, 1)      # white — neutral
	lbl.add_theme_color_override("font_color", col)
	if side == 1:
		_p1_adv_timer = ADVANTAGE_DISPLAY_TIME
	else:
		_p2_adv_timer = ADVANTAGE_DISPLAY_TIME


func _process(delta: float) -> void:
	if _p1_adv_timer > 0.0:
		_p1_adv_timer -= delta
		if _p1_adv_timer <= 0.0:
			_p1_adv_lbl.text = ""
	if _p2_adv_timer > 0.0:
		_p2_adv_timer -= delta
		if _p2_adv_timer <= 0.0:
			_p2_adv_lbl.text = ""
