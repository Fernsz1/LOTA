class_name TrainingHUD
extends CanvasLayer
## 4.1 — Training mode HUD.
## Left side (P1 + P1Dummy bars stacked): player bar on top, dummy bar below.
## Right side (P2 + P2Dummy bars stacked): same layout mirrored.
## set_health indices: 1=P1, 2=P1Dummy, 3=P2Dummy, 4=P2.

const BAR_W: float = 480.0

@onready var _p1_fill: ColorRect = $P1Bar/Fill
@onready var _p1d_fill: ColorRect = $P1DummyBar/Fill
@onready var _p2d_fill: ColorRect = $P2DummyBar/Fill
@onready var _p2_fill: ColorRect = $P2Bar/Fill
@onready var _p1_info: Label = $P1Info
@onready var _p1_dummy_info: Label = $P1DummyInfo
@onready var _p2_dummy_info: Label = $P2DummyInfo
@onready var _p2_info: Label = $P2Info


## idx: 1=P1, 2=P1Dummy, 3=P2Dummy, 4=P2.
## P1-side bars deplete from the right; P2-side bars deplete from the left.
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
