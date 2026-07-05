extends CanvasLayer
## Hand-drawn hi-fi overlay for Map Select. One full-rect Control renders every
## panel in a single _draw (skew via draw_set_transform_matrix, notches via
## draw_colored_polygon). A small ConfirmHit Control captures button clicks.

signal confirm_pressed

const DISPLAY_FONT := "res://art/fonts/Anton-Regular.ttf"
const BODY_FONT := "res://art/fonts/Oswald-VariableFont_wght.ttf"

# --- layout (1280x720 screen space) ---
const HEADER_H := 84.0
const PANEL := Rect2(884, 100, 360, 232)      # info panel (pre-skew)
const PREVIEW := Rect2(994, 490, 250, 126)    # stage preview (pre-skew)
const CONFIRM := Rect2(944, 626, 300, 60)     # confirm button (pre-skew)
const NOTCH := 16.0

# --- tokens ---
const INK := Color("#0a0904")
const PANEL_TOP := Color("#181b21")
const PANEL_BOT := Color("#0e1116")
const TXT_HI := Color("#eef1f5")
const TXT_MID := Color("#c4ccd4")
const TXT_LO := Color("#7f8a95")
const GOLD := Color("#ffcf3f")
const CONFIRM_ON := Color("#ffcf3f")
const CONFIRM_OFF := Color("#363b33")
const CONFIRM_TXT_ON := Color("#141007")
const CONFIRM_TXT_OFF := Color("#6b7066")
const RIBBON := Color("#b154ff")

var _display: FontFile
var _body: FontFile
var _overlay: Control
var _hit: Control

var _state := {}
var _ribbon_stage := ""
var _ribbon_visible := false

func _ready() -> void:
	_display = load(DISPLAY_FONT)
	_body = load(BODY_FONT)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_hit = Control.new()
	_hit.name = "ConfirmHit"
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.position = CONFIRM.position
	_hit.size = CONFIRM.size
	_hit.gui_input.connect(_on_hit_input)
	add_child(_hit)

func set_state(d: Dictionary) -> void:
	_state = d
	if _overlay:
		_overlay.queue_redraw()

func show_ribbon(stage_label: String) -> void:
	_ribbon_stage = stage_label
	_ribbon_visible = true
	if _overlay:
		_overlay.queue_redraw()
	# auto-dismiss ~1.55s (matches manager navigation delay)
	if is_inside_tree():
		await get_tree().create_timer(1.55).timeout
		_ribbon_visible = false
		if _overlay:
			_overlay.queue_redraw()

func is_ribbon_visible() -> bool:
	return _ribbon_visible

func confirm_rect_contains(p: Vector2) -> bool:
	return CONFIRM.has_point(p)

func confirm_rect_centre() -> Vector2:
	return CONFIRM.position + CONFIRM.size * 0.5

func _on_hit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_confirm_click()

## Exposed for tests + input: emit only when enabled.
func _on_confirm_click() -> void:
	if _state.get("confirm_enabled", false):
		confirm_pressed.emit()

# ---------- drawing ----------

## CSS skewX(deg): x' = x + y*tan(deg). Pivots about `origin`.
static func _skew_x(deg: float, origin: Vector2) -> Transform2D:
	var t := tan(deg_to_rad(deg))
	return Transform2D(Vector2(1.0, 0.0), Vector2(t, 1.0), origin)

func _draw_overlay() -> void:
	if _state.is_empty():
		return
	_draw_header()
	_draw_panel()
	_draw_preview()
	_draw_confirm()
	if _ribbon_visible:
		_draw_ribbon()

func _draw_header() -> void:
	_overlay.draw_rect(Rect2(0, 0, 1280, HEADER_H), Color("#080a0d"))
	var title := "MAP SELECT"
	var tw := _display.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
	var cx := 640.0 - tw.x * 0.5
	_overlay.draw_string(_display, Vector2(cx + 3, 33), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, INK)
	_overlay.draw_string(_display, Vector2(cx, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, TXT_HI)
	var flabel: String = _state.get("fighter_label", "")
	var sub := "FIGHTER:  "
	var sw := _body.get_string_size(sub + flabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	var sx := 640.0 - sw.x * 0.5
	_overlay.draw_string(_body, Vector2(sx, 58), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#cdd5dc"))
	var lead := _body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_overlay.draw_string(_body, Vector2(sx + lead, 58), flabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)

func _draw_panel() -> void:
	var xf := _skew_x(-2.0, PANEL.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := PANEL
	# hard shadow
	_overlay.draw_rect(Rect2(r.position + Vector2(11, 13), r.size), Color(0, 0, 0, 0.9))
	# border + gradient body (two-band approximation of the vertical gradient)
	_overlay.draw_rect(r, INK)
	var inner := r.grow(-5.0)
	_overlay.draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.5)), PANEL_TOP)
	_overlay.draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.5),
		Vector2(inner.size.x, inner.size.y * 0.5)), PANEL_BOT)
	# accent strip
	var accent: Color = _state.get("accent", Color("#4a5058"))
	_overlay.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 6)), accent)
	# text
	var x := inner.position.x + 17
	var y := inner.position.y + 26
	_overlay.draw_string(_body, Vector2(x, y), _state.get("kicker", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
	y += 30
	_overlay.draw_string(_display, Vector2(x, y), _state.get("region_name", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#f2f4f7"))
	var nmw := _display.get_string_size(_state.get("region_name", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	_overlay.draw_string(_body, Vector2(x + nmw + 8, y), _state.get("region_no", ""),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#8b94a0"))
	y += 20
	# dashed divider
	var dx := x
	while dx < inner.position.x + inner.size.x - 17:
		_overlay.draw_rect(Rect2(dx, y, 10, 2), Color("#3a4049"))
		dx += 16
	y += 22
	_draw_kv(x, y, "FIGHTER", _state.get("fighter", ""), GOLD); y += 24
	_draw_kv(x, y, "STAGE", _state.get("stage", ""), Color("#e7edf2")); y += 24
	_draw_kv(x, y, "CONTEXT", "", TXT_MID)
	_overlay.draw_multiline_string(_body, Vector2(x + 78, y), _state.get("story", ""),
		HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 95, 13, 3, Color("#aab3bc"))
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_kv(x: float, y: float, key: String, val: String, val_col: Color) -> void:
	_overlay.draw_string(_body, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TXT_LO)
	if val != "":
		_overlay.draw_string(_body, Vector2(x + 78, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, val_col)

func _draw_preview() -> void:
	var xf := _skew_x(-2.0, PREVIEW.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := PREVIEW
	_overlay.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.9))
	_overlay.draw_rect(r, INK)
	var inner := r.grow(-5.0)
	_overlay.draw_rect(inner, Color("#161920"))
	# diagonal stripes
	var accent: Color = _state.get("accent", Color("#4a5058"))
	var stage: String = _state.get("stage", "—")
	_overlay.draw_string(_body, inner.position + Vector2(14, 22), "STAGE PREVIEW",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#6f7883"))
	_overlay.draw_string(_display, inner.position + Vector2(14, 52), stage,
		HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 24, 18, Color("#e7edf2"))
	_overlay.draw_string(_body, inner.position + Vector2(14, inner.size.y - 12),
		"[ drop stage art · 16:9 ]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#5c646d"))
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_confirm() -> void:
	var enabled: bool = _state.get("confirm_enabled", false)
	var xf := _skew_x(-3.0, CONFIRM.position)
	_overlay.draw_set_transform_matrix(xf)
	var r := CONFIRM
	_overlay.draw_polygon(_notched(Rect2(r.position + Vector2(8, 11), r.size)),
		PackedColorArray([Color(0, 0, 0, 1)]))
	_overlay.draw_polygon(_notched(r), PackedColorArray([INK]))
	_overlay.draw_polygon(_notched(r.grow(-5.0)),
		PackedColorArray([CONFIRM_ON if enabled else CONFIRM_OFF]))
	var label := "CONFIRM SELECTION"
	var lw := _display.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_overlay.draw_string(_display, r.position + Vector2((r.size.x - lw) * 0.5, 40), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CONFIRM_TXT_ON if enabled else CONFIRM_TXT_OFF)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)

## Rectangle with the top-left + bottom-right corners notched (clip-path style).
static func _notched(r: Rect2) -> PackedVector2Array:
	var p := r.position
	var s := r.size
	return PackedVector2Array([
		p + Vector2(NOTCH, 0), p + Vector2(s.x, 0),
		p + Vector2(s.x, s.y - NOTCH), p + Vector2(s.x - NOTCH, s.y),
		p + Vector2(0, s.y), p + Vector2(0, NOTCH)])

func _draw_ribbon() -> void:
	var centre := Vector2(640, 360)
	var size := Vector2(520, 108)
	var r := Rect2(centre - size * 0.5, size)
	var xf := _skew_x(-5.0, centre)
	_overlay.draw_set_transform_matrix(xf)
	_overlay.draw_rect(Rect2(r.position + Vector2(12, 14), r.size), Color(0, 0, 0, 1))
	_overlay.draw_rect(r, INK)
	_overlay.draw_rect(r.grow(-6.0), RIBBON)
	var kicker := "STAGE LOCKED"
	var kw := _body.get_string_size(kicker, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	_overlay.draw_string(_body, Vector2(centre.x - kw * 0.5, r.position.y + 36), kicker,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#1a0d29"))
	var sw := _display.get_string_size(_ribbon_stage, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	_overlay.draw_string(_display, Vector2(centre.x - sw * 0.5, r.position.y + 82), _ribbon_stage,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
