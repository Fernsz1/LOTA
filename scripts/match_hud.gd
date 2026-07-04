extends CanvasLayer
## Match HUD (2.6): a gritty cel-shaded combat overlay — portrait plates, fighter
## names, archetype chips, health bars, SIGABO super meters, a round timer, round
## pips, and an announce line. Cosmetic only: MatchManager pushes values in; this
## never reads or writes game state. Value tweening is a rendering-only concern.

# 7.4 fix: player badge, fighter name, round pips, timer, and round counter
# are branding, not a per-side callout — they must read as ONE consistent
# accent (matching the main-menu title-glow orange) regardless of which
# player/character they belong to. Previously set_fighter() recolored the
# name/pips to the picked character's own signature color (CharacterData.color),
# so P1 showed whatever hue the selected character happened to have — a
# different color every match; the timer/round labels were a separate,
# unrelated gold. The health bar, ult meter, and portrait frame are handled
# separately below — they DO want dynamic per-character color, just routed
# through the recolor shader instead of raw modulate.
const PLAYER_ACCENT := Color(0.91, 0.518, 0.173, 1)   # matches main_menu.tscn title glow

const TIMER_WARN: int = 10
const TIMER_OK := PLAYER_ACCENT
const TIMER_LOW := Color(1, 0.231, 0.231, 1)   # #ff3b3b — kept: a deliberate "time's running out" danger cue, not branding
const PIP_OFF := Color(0.149, 0.149, 0.18, 1)  # #26262e

const METER_FILL := {
	1: preload("res://assets/hud/meter_fill_blue.png"),
	2: preload("res://assets/hud/meter_fill_red.png"),
}
const METER_FILL_READY := preload("res://assets/hud/meter_fill_green.png")

# 7.4 — health bar (per-character) and ult meter (brand orange) both need to
# recolor the SAME pre-colored fill art (health_fill_blue/red.png,
# meter_fill_blue/red.png) to an arbitrary target hue. A plain `modulate`
# multiplies against those non-white pixels, so the same tint would render a
# different effective color depending on which side's (blue vs red) art it
# sits on — the shader strips the source down to luminance first, so the
# result depends only on the `tint` uniform, never on the source asset.
const RECOLOR_SHADER := preload("res://shaders/hud_recolor.gdshader")

const FLASH_TIME: float = 0.17
const BLINK_TIME: float = 0.35   # half-cycle; full blink ~0.7s
# LoL-style trailing bar (7.4): the main fill snaps to the new value instantly;
# a second bar behind it holds the OLD value and drains down to match after a
# short hold, so a drop reads as an orange chunk peeling off the current bar.
const TRAIL_HOLD: float = 0.15
const TRAIL_TIME: float = 0.55

@onready var _portrait := {1: $HUD/P1/Portrait, 2: $HUD/P2/Portrait}
@onready var _health := {1: $HUD/P1/Health, 2: $HUD/P2/Health}
@onready var _health_trail := {1: $HUD/P1/HealthTrail, 2: $HUD/P2/HealthTrail}
@onready var _flash := {1: $HUD/P1/Health/Flash, 2: $HUD/P2/Health/Flash}
@onready var _meter := {1: $HUD/P1/MeterRow/MeterStack/Meter, 2: $HUD/P2/MeterRow/MeterStack/Meter}
@onready var _meter_trail := {
	1: $HUD/P1/MeterRow/MeterStack/MeterTrail, 2: $HUD/P2/MeterRow/MeterStack/MeterTrail,
}
@onready var _super_ready := {1: $HUD/P1/MeterRow/Ready, 2: $HUD/P2/MeterRow/Ready}
@onready var _name := {1: $HUD/P1/Name, 2: $HUD/P2/Name}
@onready var _pips := {
	1: [$HUD/P1/Pips/Pip0, $HUD/P1/Pips/Pip1],
	2: [$HUD/P2/Pips/Pip0, $HUD/P2/Pips/Pip1],
}
@onready var _timer: Label = $HUD/Center/TimerPlate/Timer
@onready var _round: Label = $HUD/Center/Round
@onready var _announce: Label = $HUD/Center/Announce

var _hp_target := {1: 1.0, 2: 1.0}
var _meter_target := {1: 0.0, 2: 0.0}
var _hp_trail_tween := {1: null, 2: null}
var _meter_trail_tween := {1: null, 2: null}
var _blink := {1: null, 2: null}
var _health_material := {1: null, 2: null}     # ShaderMaterial, recolor.tint = fighter's color
var _meter_material := {1: null, 2: null}      # ShaderMaterial, recolor.tint = PLAYER_ACCENT
var _portrait_material := {1: null, 2: null}   # ShaderMaterial, recolor.tint = fighter's color

func _ready() -> void:
	# The P1/P2 fill art (health_fill_blue/red.png, meter_fill_blue/red.png) is
	# pre-colored, not neutral — modulate MULTIPLIES against those pixels, so
	# tinting them orange for the trail bar would render a different effective
	# hue per side (blue*orange != red*orange) and per bar. A flat white
	# texture makes `texture * modulate == modulate`, so all four trail bars
	# show the exact same orange regardless of which fill they sit behind.
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(img)
	for player in [1, 2]:
		_health_trail[player].texture_progress = white
		_meter_trail[player].texture_progress = white
	# Health always shows the recolor shader (permanent per-character tint);
	# the meter toggles it on/off in set_meter() (off for the true-green ready
	# texture, on while charging). Each bar gets its OWN material instance —
	# they share the Shader resource, but the `tint` uniform lives on the
	# material, so one shared instance would force all four bars to match.
	for player in [1, 2]:
		_health_material[player] = ShaderMaterial.new()
		_health_material[player].shader = RECOLOR_SHADER
		_health[player].material = _health_material[player]
		_meter_material[player] = ShaderMaterial.new()
		_meter_material[player].shader = RECOLOR_SHADER
		_meter_material[player].set_shader_parameter("tint", PLAYER_ACCENT)
		# Portrait frame (portrait_plate_p1/p2.png): same pre-colored-art
		# problem as the health bar, same fix — the Img/Badge children are
		# separate CanvasItems, so tinting Portrait's own material doesn't
		# touch them.
		_portrait_material[player] = ShaderMaterial.new()
		_portrait_material[player].shader = RECOLOR_SHADER
		_portrait[player].material = _portrait_material[player]

func set_health(player: int, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	if f < _hp_target[player]:
		_pulse_flash(player)
	_hp_target[player] = f
	_hp_trail_tween[player] = _update_bar(
			_health[player], _health_trail[player], _hp_trail_tween[player], f)

func _pulse_flash(player: int) -> void:
	var overlay: ColorRect = _flash[player]
	overlay.modulate.a = 1.0
	var t := overlay.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, FLASH_TIME)

func set_meter(player: int, frac: float) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	_meter_target[player] = f
	var bar: TextureProgressBar = _meter[player]
	_meter_trail_tween[player] = _update_bar(bar, _meter_trail[player], _meter_trail_tween[player], f)
	var ready: bool = f >= 1.0
	if ready:
		# The ready swap is its own true-green art — showing it THROUGH the
		# recolor shader would flatten it to grayscale (tint would be white),
		# so drop the material entirely and let it render un-tinted.
		bar.texture_progress = METER_FILL_READY
		bar.material = null
	else:
		bar.texture_progress = METER_FILL[player]
		bar.material = _meter_material[player]   # 7.4: the recharge bar is brand orange
	if ready:
		_start_blink(player)
	else:
		_stop_blink(player)

## Instantly moves `bar` to the new value. If the value dropped, `trail` is left
## sitting at the old (larger) value and eased down to the new one after a
## short hold — the sliver of `trail` peeking out past `bar` in that window is
## the LoL-style "recently lost" chunk. Returns the (possibly new) trail tween
## so the caller can store it and kill it on the next call.
func _update_bar(bar: TextureProgressBar, trail: TextureProgressBar,
		running_trail_tween: Tween, f: float) -> Tween:
	var old_value: float = bar.value
	bar.value = f * 100.0
	if running_trail_tween != null:
		running_trail_tween.kill()
	if f * 100.0 < old_value:
		trail.value = old_value
		var t := trail.create_tween()
		t.tween_interval(TRAIL_HOLD)
		t.tween_property(trail, "value", f * 100.0, TRAIL_TIME).set_trans(Tween.TRANS_SINE)
		return t
	trail.value = f * 100.0
	return null

func _start_blink(player: int) -> void:
	# SUPER READY! keeps its reserved layout slot always (matches the mock); only its
	# opacity animates, so the meter never reflows when the ready state flips.
	var label: Label = _super_ready[player]
	label.modulate.a = 1.0
	if _blink[player] != null and _blink[player].is_running():
		return
	var t := label.create_tween().set_loops()
	t.tween_property(label, "modulate:a", 0.2, BLINK_TIME)
	t.tween_property(label, "modulate:a", 1.0, BLINK_TIME)
	_blink[player] = t

func _stop_blink(player: int) -> void:
	if _blink[player] != null:
		_blink[player].kill()
		_blink[player] = null
	_super_ready[player].modulate.a = 0.0

func set_timer(seconds: int) -> void:
	_timer.text = "%02d" % seconds
	_timer.label_settings.font_color = TIMER_LOW if seconds <= TIMER_WARN else TIMER_OK

func set_rounds(player: int, won: int) -> void:
	var pips: Array = _pips[player]
	for i in pips.size():
		pips[i].color = PLAYER_ACCENT if i < won else PIP_OFF

## The name text stays PLAYER_ACCENT regardless of who's selected (see the
## const comment) — but the health bar and portrait frame ARE meant to track
## each fighter's own signature color, via the recolor shader's tint uniform.
func set_fighter(player: int, fighter_name: String, color: Color) -> void:
	_name[player].text = fighter_name
	_health_material[player].set_shader_parameter("tint", color)
	_portrait_material[player].set_shader_parameter("tint", color)

## The small persistent round counter next to the timer (distinct from the
## big centered announce() line, which clears after the round-intro beat).
func set_round(n: int) -> void:
	_round.text = "ROUND %d" % n

func announce(text: String) -> void:
	_announce.text = text

func snap() -> void:
	for p in [1, 2]:
		if _hp_trail_tween[p] != null:
			_hp_trail_tween[p].kill()
			_hp_trail_tween[p] = null
		if _meter_trail_tween[p] != null:
			_meter_trail_tween[p].kill()
			_meter_trail_tween[p] = null
		_health[p].value = _hp_target[p] * 100.0
		_health_trail[p].value = _hp_target[p] * 100.0
		_meter[p].value = _meter_target[p] * 100.0
		_meter_trail[p].value = _meter_target[p] * 100.0
