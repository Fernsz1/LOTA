class_name TrainingHUD
extends CanvasLayer
## 4.2/7.5 — Training extras over the match HUD. The shared match frame (the
## two HUMANS' portraits, names, health bars, meters) comes from a MatchHUD
## instance in the scene. Each side's DUMMY gets a compact block tucked right
## under its player's meter, styled like a shrunken player plate: the Bangers
## name treatment and the same health track/fill art, recolored orange through
## the hud_recolor shader (both baked in training_hud.tscn). A slim bottom
## strip carries the live move readout, frame advantage, and hotkey hints.
## Sits on layer 2 so it stacks above the match HUD (layer 1).

const ADVANTAGE_DISPLAY_TIME: float = 3.0   # seconds before advantage label clears

@onready var _move_lbl := {1: $Strip/Row/Left/MoveReadout, 2: $Strip/Row/Right/MoveReadout}
@onready var _adv_lbl := {1: $Strip/Row/Left/Advantage, 2: $Strip/Row/Right/Advantage}
@onready var _dummy_status := {1: $P1Dummy/Status, 2: $P2Dummy/Status}
@onready var _dummy_bar := {1: $P1Dummy/Bar, 2: $P2Dummy/Bar}

var _adv_timer := {1: 0.0, 2: 0.0}
var _player_infinite := {1: false, 2: false}


## 4.2 — Live move readout: move name, frame data, and current phase.
## side: 1=P1 (left), 2=P2 (right). move may be null when no attack is active.
func set_move_readout(side: int, move: MoveData, fis: int) -> void:
	var lbl: Label = _move_lbl[side]
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


## 4.2 — Frame advantage after a hit or block. Positive = attacker acts first.
## side is the ARENA (1 = left, 2 = right). Auto-clears after a few seconds.
func show_advantage(side: int, adv: int) -> void:
	var lbl: Label = _adv_lbl[side]
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
	_adv_timer[side] = ADVANTAGE_DISPLAY_TIME


func set_dummy_status(side: int, mode_label: String, infinite: bool) -> void:
	_dummy_status[side].text = "DUMMY · %s%s%s" % [
		mode_label,
		"  ♥INF" if infinite else "",
		"    P%d ♥INF" % side if _player_infinite[side] else "",
	]


func set_player_status(side: int, infinite: bool) -> void:
	# Folded into the dummy-status line to keep the block compact; remember it
	# so the next set_dummy_status doesn't drop the flag.
	_player_infinite[side] = infinite
	var cur: String = _dummy_status[side].text
	var base: String = cur.split("    ")[0]
	_dummy_status[side].text = base + ("    P%d ♥INF" % side if infinite else "")


## Compact HP bar for each side's dummy — the match health-bar art in
## miniature (P2's fill_mode mirrors the match HUD's inner-edge depletion).
func set_dummy_health(side: int, frac: float) -> void:
	_dummy_bar[side].value = clampf(frac, 0.0, 1.0) * 100.0


func _process(delta: float) -> void:
	for side in [1, 2]:
		if _adv_timer[side] > 0.0:
			_adv_timer[side] -= delta
			if _adv_timer[side] <= 0.0:
				_adv_lbl[side].text = ""
