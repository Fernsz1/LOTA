extends Control
## Post-select VS card: shows both locked-in fighters as full busts before the
## match starts. Auto-advances after DISPLAY_SECONDS, or immediately on any key.
##
## Reuses the character-select visual language (7.2/7.6): each side pairs the
## fighter's stage bg (accent-washed) with a used-rect bust leaning toward the
## centre VS badge, an accent name/tag plate, and the same parallelogram skew —
## so the intro reads as the same screen family, not a bare placeholder card.

const DISPLAY_SECONDS := 2.5

const ART_DIR := "res://assets/char-select/"
const BEBAS := preload("res://art/fonts/BebasNeue-Regular.ttf")
const SKEW_SHADER := preload("res://art/ui/skew.gdshader")
const SKEW_AMOUNT := 0.05

const INK := Color(0.047, 0.031, 0.024, 1)
const BONE := Color(0.957, 0.929, 0.886, 1)
const MUTED := Color(0.6, 0.56, 0.48, 1)

# Display-only archetype tag, mirrored from character_select's STYLE_TAGS so the
# name plate matches the roster copy. Unlisted ids fall back to GENERIC_TAG.
const STYLE_TAGS := {
	"jerb": "ALL-ROUNDER",
	"rainne": "STRIKER",
	"jacob": "GRAPPLER",
	"sofia": "SKIRMISHER",
	"luis": "ZONER",
}
const GENERIC_TAG := "FIGHTER"

@onready var _p1_panel: PanelContainer = $Split/P1Panel
@onready var _p2_panel: PanelContainer = $Split/P2Panel

var _advanced: bool = false
var _used_rect_cache: Dictionary = {}


func _ready() -> void:
	# Panel rects resolve at end-of-frame; building now would read zero sizes and
	# mis-scale the busts, so defer until the HBox has been sorted.
	call_deferred("_build")


func _build() -> void:
	_build_side(_p1_panel, 1)
	_build_side(_p2_panel, 2)
	await get_tree().create_timer(DISPLAY_SECONDS).timeout
	_advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_advance()


func _advance() -> void:
	if _advanced:
		return
	_advanced = true
	if MatchSelection.pending_scene != null:
		get_tree().change_scene_to_packed(MatchSelection.pending_scene)
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")


## Folder id for a CharacterData (res://characters/<id>/<id>_data.tres -> <id>),
## which is also the art filename stem in ART_DIR.
func _id_of(data) -> String:
	if data == null:
		return ""
	return data.resource_path.get_base_dir().get_file()


func _art_path(id: String, kind: String) -> String:
	return "%s%s_%s.png" % [ART_DIR, id, kind]


func _load_art(id: String, kind: String) -> Texture2D:
	if id == "":
		return null
	var path := _art_path(id, kind)
	return load(path) if ResourceLoader.exists(path) else null


## Bounding rect (source pixels) of the art's non-transparent content, so framing
## keys off the head/body instead of the canvas. Mirrors character_select.
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


## Places art as a bust: figure scaled so its visible body is `vert_fill`x the
## container height, head pinned just below the top edge, biased toward one side
## (+1 right, -1 left). Requires the parent to clip_contents.
func _add_bust_art(parent: Control, container: Vector2, tex: Texture2D, vert_fill: float, side: float) -> void:
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
	var head_y := container.y * 0.05
	var target_cx := container.x * 0.5 + side * (container.x * 0.15)
	var content_cx := (content.position.x + content.size.x * 0.5) * scale
	var content_top := content.position.y * scale
	art.position = Vector2(target_cx - content_cx, head_y - content_top)
	parent.add_child(art)


## Builds one fighter side into its preview panel: stage bg + accent wash, a bust
## leaning toward the VS centre, a P# READY badge, and a name/tag plate — then the
## whole panel is sheared to match the character-select cards.
func _build_side(panel: PanelContainer, player: int) -> void:
	var data = MatchSelection.p1_data if player == 1 else MatchSelection.p2_data
	var accent: Color = MatchSelection.p1_color if player == 1 else MatchSelection.p2_color
	var id := _id_of(data)
	var fighter_name: String = data.character_name.to_upper() if data else "P%d" % player
	var tag: String = STYLE_TAGS.get(id, GENERIC_TAG)

	for child in panel.get_children():
		child.queue_free()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.clip_contents = true
	panel.add_child(root)

	var bg := _load_art(id, "bg")
	if bg != null:
		var bg_rect := TextureRect.new()
		bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.texture = bg
		root.add_child(bg_rect)
	else:
		# No art (e.g. scene run directly): fall back to the signature accent fill.
		var fill := ColorRect.new()
		fill.set_anchors_preset(Control.PRESET_FULL_RECT)
		fill.color = Color(accent, 0.55)
		root.add_child(fill)

	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(accent, 0.16)
	root.add_child(wash)

	# P1 leans right toward the badge, P2 leans left — same as the select panels.
	_add_bust_art(root, panel.size, _load_art(id, "transparent"),
		1.5, 1.0 if player == 1 else -1.0)

	# bottom name/tag plate
	var info := PanelContainer.new()
	info.anchor_left = 0.0
	info.anchor_right = 1.0
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_top = -96.0
	info.offset_bottom = 0.0
	info.add_theme_stylebox_override("panel", _info_stylebox(accent))
	root.add_child(info)

	var align := HORIZONTAL_ALIGNMENT_LEFT if player == 1 else HORIZONTAL_ALIGNMENT_RIGHT
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	info.add_child(box)

	var name_label := Label.new()
	name_label.text = fighter_name
	name_label.horizontal_alignment = align
	name_label.add_theme_font_override("font", BEBAS)
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", BONE)
	name_label.add_theme_color_override("font_outline_color", INK)
	name_label.add_theme_constant_override("outline_size", 6)
	box.add_child(name_label)

	var tag_label := Label.new()
	tag_label.text = tag
	tag_label.horizontal_alignment = align
	tag_label.add_theme_font_size_override("font_size", 15)
	tag_label.add_theme_color_override("font_color", accent)
	box.add_child(tag_label)

	# P# READY corner badge
	var badge := Label.new()
	badge.text = "P%d  //  READY" % player
	badge.add_theme_font_override("font", BEBAS)
	badge.add_theme_font_size_override("font_size", 28)
	badge.add_theme_color_override("font_color", INK)
	badge.add_theme_stylebox_override("normal", _badge_stylebox(accent))
	# Held in a hair from the corners so the skew's shift keeps them fully inside.
	badge.offset_top = 14.0
	if player == 1:
		badge.offset_left = 20.0
	else:
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -20.0
	root.add_child(badge)

	_apply_skew(panel)


func _info_stylebox(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.031, 0.024, 0.92)
	sb.border_width_top = 4
	sb.border_color = accent
	# Extra side padding so the skew's horizontal shift never pushes the name off
	# the panel's clipped edge.
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb


# Pushes a colour to full neon so muted signature colours still read as glowing.
func _neon(c: Color) -> Color:
	return Color.from_hsv(c.h, clampf(c.s + 0.25, 0.7, 1.0), 1.0, 1.0)


func _badge_stylebox(accent: Color) -> StyleBoxFlat:
	var neon := _neon(accent)
	var sb := StyleBoxFlat.new()
	sb.bg_color = neon
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.85)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(neon.r, neon.g, neon.b, 0.6)
	sb.shadow_size = 13
	sb.shadow_offset = Vector2.ZERO
	return sb


## Shears the whole panel into a leaning parallelogram, pivoting about its centre,
## by assigning one world-space skew material to every CanvasItem in the subtree.
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
