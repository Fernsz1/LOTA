extends Control
## Post-match "hero" results screen (2.6). Reached once MatchManager holds on the
## deciding win. Shows the winning player's entered name as the banner, their
## character rendered as a full-screen bust over that character's stage bg with a
## signature-accent wash, and a skewed "PLAYER n // AS <CHAR>" badge. Routes:
## Rematch -> Character Select, Main Menu -> Main Menu.
##
## The bust/skew helpers are ported from character_select.gd and kept self-contained
## here rather than shared this pass (see .local design doc, "Reuse note").

const ART_DIR := "res://assets/char-select/"
const BEBAS := preload("res://art/fonts/BebasNeue-Regular.ttf")
const SKEW_SHADER := preload("res://art/ui/skew.gdshader")
const SKEW_AMOUNT := 0.1

const INK := Color(0.047, 0.031, 0.024, 1)

@onready var _hero: Control = $HeroLayer
@onready var _title: Label = $Title

var _used_rect_cache: Dictionary = {}


func _ready() -> void:
	var winner: int = MatchSelection.winner
	var data: CharacterData = MatchSelection.p1_data if winner == 1 else MatchSelection.p2_data
	var accent: Color = MatchSelection.p1_color if winner == 1 else MatchSelection.p2_color
	var player_name: String = MatchSelection.p1_name if winner == 1 else MatchSelection.p2_name

	# Banner = the entered player name.
	_style_title(accent)
	_title.text = "%s WINS" % player_name.to_upper()

	if data == null:
		# No character / stub: dark backdrop + text-only badge, never crash.
		var backdrop := ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0.05, 0.05, 0.07, 1)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero.add_child(backdrop)
		_add_badge(winner, "P%d" % winner, accent)
		return

	var id := data.resource_path.get_base_dir().get_file()
	var char_name := data.character_name.to_upper()

	# Layer 1: stage background (skipped cleanly if the art is missing).
	var bg_tex := _load_art(id, "bg")
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture = bg_tex
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hero.add_child(bg)

	# Layer 2: accent wash over the bg.
	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(accent, 0.18)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(wash)

	# Layers 3 + 5 (bust then badge) are built after layout resolves so the bust
	# framing reads a real HeroLayer size and the skew pivot is valid. Adding them
	# in this order keeps draw order correct: bg, wash, bust, badge. The Title
	# banner (Layer 4) is a sibling above HeroLayer, so it always stays on top.
	call_deferred("_build_hero", id, winner, char_name, accent)


func _build_hero(id: String, winner: int, char_name: String, accent: Color) -> void:
	# head_frac 0.22 drops the head below the top-centre "... WINS" banner so the
	# name never overlaps the face; centred (side 0) as a single triumphant hero.
	_add_bust_art(_hero, _hero.size, _load_art(id, "transparent"), 1.35, 0.0, 0.22)
	_add_badge(winner, char_name, accent)


func _add_badge(winner: int, char_name: String, accent: Color) -> void:
	var badge := PanelContainer.new()
	badge.anchor_left = 0.5
	badge.anchor_right = 0.5
	badge.anchor_top = 1.0
	badge.anchor_bottom = 1.0
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = -132.0
	badge.offset_bottom = -72.0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _badge_stylebox(accent))

	var label := Label.new()
	label.text = "PLAYER %d  //  AS %s" % [winner, char_name]
	label.add_theme_font_override("font", BEBAS)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", INK)
	badge.add_child(label)

	_hero.add_child(badge)
	# Skew after layout resolves so the badge's global_rect (skew pivot) is valid.
	call_deferred("_apply_skew", badge)


func _style_title(accent: Color) -> void:
	_title.add_theme_font_override("font", BEBAS)
	_title.add_theme_font_size_override("font_size", 72)
	_title.add_theme_color_override("font_color", accent)
	_title.add_theme_color_override("font_outline_color", INK)
	_title.add_theme_constant_override("outline_size", 8)


# --- ported from character_select.gd ---------------------------------------

func _art_path(id: String, kind: String) -> String:
	return "%s%s_%s.png" % [ART_DIR, id, kind]


func _load_art(id: String, kind: String) -> Texture2D:
	var path := _art_path(id, kind)
	return load(path) if ResourceLoader.exists(path) else null


func _content_rect(tex: Texture2D) -> Rect2:
	var key := tex.resource_path
	if _used_rect_cache.has(key):
		return _used_rect_cache[key]
	var rect := Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	var img := tex.get_image()
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			rect = Rect2(used.position, used.size)
	_used_rect_cache[key] = rect
	return rect


func _add_bust_art(parent: Control, container: Vector2, tex: Texture2D, vert_fill: float, side: float, head_frac: float = 0.05) -> void:
	if tex == null:
		return
	var content := _content_rect(tex)
	var scale := container.y * vert_fill / content.size.y
	var art := TextureRect.new()
	art.texture = tex
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.size = Vector2(tex.get_width(), tex.get_height()) * scale
	var head_y := container.y * head_frac
	var target_cx := container.x * 0.5 + side * (container.x * 0.15)
	var content_cx := (content.position.x + content.size.x * 0.5) * scale
	var content_top := content.position.y * scale
	art.position = Vector2(target_cx - content_cx, head_y - content_top)
	parent.add_child(art)


func _neon(c: Color) -> Color:
	return Color.from_hsv(c.h, clampf(c.s + 0.25, 0.7, 1.0), 1.0, 1.0)


func _badge_stylebox(accent: Color) -> StyleBoxFlat:
	var neon := _neon(accent)
	var sb := StyleBoxFlat.new()
	sb.bg_color = neon
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.85)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(neon.r, neon.g, neon.b, 0.6)
	sb.shadow_size = 13
	sb.shadow_offset = Vector2.ZERO
	return sb


func _apply_skew(node: CanvasItem) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SKEW_SHADER
	mat.set_shader_parameter("shear", SKEW_AMOUNT)
	mat.set_shader_parameter("pivot_y", node.get_global_rect().get_center().y)
	_assign_material(node, mat)


func _assign_material(node: CanvasItem, mat: Material) -> void:
	node.material = mat
	for child in node.get_children():
		if child is CanvasItem:
			_assign_material(child, mat)


func _on_rematch_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
