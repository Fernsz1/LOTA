extends Control
## Tekken-style select screen. Both players share one grid; each moves their own
## cursor with p{n}_left/right, locks in with p{n}_fast, and unlocks with p{n}_heavy.
##
## 7.2 — roster is data-driven: every folder under characters/ with a matching
## <id>/<id>_data.tres is auto-discovered and shown unlocked. Nothing here needs
## editing to add a character — drop the folder + resource in and it appears.
## ROSTER_ORDER is display-order only (unlisted ids sort after it, alphabetically);
## slots are padded with locked "???" stubs up to ROSTER_SIZE so the full planned
## roster size reads correctly before every character is built.

const CHARACTERS_DIR := "res://characters/"
const ROSTER_ORDER: Array[String] = ["jerb", "rainne", "luis", "sofia", "jacob"]
const ROSTER_SIZE := 5
const LOCKED_COLOR := Color(0.22, 0.22, 0.25, 1)

# Display-only archetype tag shown under each fighter's name (a UI concern, so it
# lives here rather than in CharacterData — same spirit as ROSTER_ORDER above).
# Unlisted ids fall back to GENERIC_TAG; locked stubs use LOCKED_TAG.
const STYLE_TAGS := {
	"jerb": "ALL-ROUNDER",
	"rainne": "STRIKER",
	"jacob": "GRAPPLER",
	"sofia": "SKIRMISHER",
	"luis": "ZONER",
}
const GENERIC_TAG := "FIGHTER"
const LOCKED_TAG := "COMING SOON"

# Short lore/playstyle blurb shown under each fighter's name in the preview panel
# (UI copy, so it lives here alongside STYLE_TAGS rather than in CharacterData).
const DESCRIPTIONS := {
	"jerb": "A disciplined boxer with no glaring weakness. Rewards clean fundamentals and relentless pressure.",
	"rainne": "Explosive striker who turns the smallest opening into damage with fast, punishing combos.",
	"luis": "Master of the rattan sticks. Controls mid-range with precise strikes and lethal counters.",
	"sofia": "Agile and explosive. Uses fast kicks, footwork, and combinations to overwhelm foes.",
	"jacob": "Overpowering grappler. Closes the gap, clinches, and ends the fight up close.",
}
const GENERIC_DESC := "A seasoned brawler ready to prove themselves in the arena."
const LOCKED_DESC := "A mysterious challenger, yet to step into the light."

const SLOT_SIZE := Vector2(212, 150)
const CURSOR_MARGIN := 6.0

const ART_DIR := "res://assets/char-select/"
const BEBAS := preload("res://art/fonts/BebasNeue-Regular.ttf")

const INK := Color(0.047, 0.031, 0.024, 1)
const BONE := Color(0.957, 0.929, 0.886, 1)
const MUTED := Color(0.6, 0.56, 0.48, 1)

@onready var _roster_strip: HBoxContainer = $RosterStrip
@onready var _p1_panel: PanelContainer = $Split/P1Panel
@onready var _p2_panel: PanelContainer = $Split/P2Panel
@onready var _p1_cursor: Control = $P1Cursor
@onready var _p2_cursor: Control = $P2Cursor
@onready var _p1_status: Label = $StatusRow/P1Status
@onready var _p2_status: Label = $StatusRow/P2Status

var _slots: Array[Dictionary] = []
var _slot_nodes: Array[Control] = []
var _p1_slot: int = 0
var _p2_slot: int = 1
var _p1_locked: bool = false
var _p2_locked: bool = false
var _advanced: bool = false


func _art_path(id: String, kind: String) -> String:
	# kind is "transparent" or "bg"
	return "%s%s_%s.png" % [ART_DIR, id, kind]


func _load_art(id: String, kind: String) -> Texture2D:
	var path := _art_path(id, kind)
	return load(path) if ResourceLoader.exists(path) else null


## Bounding rect (in source pixels) of each art's non-transparent content, so
## framing keys off the actual head/body instead of the canvas — the arts have
## wildly different headroom (Sofia sits low in a tall 887×1774 canvas, Jerb
## nearly fills a 1023×1537 one), which is why a naive top-pin cropped some
## faces off. Cached per texture path; get_used_rect scans once.
var _used_rect_cache: Dictionary = {}


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


## Places character art as a "bust": the whole figure is scaled so its visible
## body (from get_used_rect) is `vert_fill`× the container height, then the head
## is pinned just below the top edge and the figure biased toward one side
## (+1 = right, -1 = left, 0 = centred). vert_fill > 1 means the legs fall past
## the bottom and get clipped, leaving a head-to-hip framing like the mock.
## Requires the parent to clip_contents.
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
	# Land the head a hair below the top edge, and the body's horizontal centre
	# at the biased target x.
	var head_y := container.y * 0.05
	var target_cx := container.x * 0.5 + side * (container.x * 0.15)
	var content_cx := (content.position.x + content.size.x * 0.5) * scale
	var content_top := content.position.y * scale
	art.position = Vector2(target_cx - content_cx, head_y - content_top)
	parent.add_child(art)


func _ready() -> void:
	_slots = _build_roster()
	for i in _slots.size():
		_slot_nodes.append(_build_slot(_slots[i], i))
	# Container layout resolves at end-of-frame; positioning cursors now would read
	# stale (zero) rects, so defer until the row has actually been sorted.
	call_deferred("_init_cursors")


## Scans characters/ for <id>/<id>_data.tres, loads whatever exists, sorts by
## ROSTER_ORDER (unlisted ids alphabetically after it), then pads with locked
## stubs up to ROSTER_SIZE.
func _build_roster() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(CHARACTERS_DIR)
	if dir:
		dir.list_dir_begin()
		var folder := dir.get_next()
		while folder != "":
			if dir.current_is_dir():
				var path := "%s%s/%s_data.tres" % [CHARACTERS_DIR, folder, folder]
				if ResourceLoader.exists(path):
					var data: CharacterData = load(path)
					found.append({
						"id": folder, "locked": false,
						"name": data.character_name.to_upper(),
						"tag": STYLE_TAGS.get(folder, GENERIC_TAG),
						"color": data.color, "data": data,
					})
			folder = dir.get_next()
		dir.list_dir_end()

	found.sort_custom(_by_roster_order)

	while found.size() < ROSTER_SIZE:
		found.append({"id": "", "locked": true, "name": "???", "tag": LOCKED_TAG, "color": LOCKED_COLOR, "data": null})
	return found


func _by_roster_order(a: Dictionary, b: Dictionary) -> bool:
	var ai: int = ROSTER_ORDER.find(a["id"])
	var bi: int = ROSTER_ORDER.find(b["id"])
	if ai == -1: ai = 999
	if bi == -1: bi = 999
	if ai != bi:
		return ai < bi
	return a["id"] < b["id"]


## Compact comic roster tile: fighter art over an accent fill, a number chip
## top-left, and an outlined name + accent tag over a dark scrim at the bottom.
## Locked stubs get a dark fill with a big "?".
func _build_slot(slot: Dictionary, index: int) -> Control:
	var locked: bool = slot["locked"]
	var accent: Color = slot["color"]
	var tile := PanelContainer.new()
	tile.custom_minimum_size = SLOT_SIZE
	tile.clip_contents = true
	tile.theme_type_variation = "RosterTile"

	var root := Control.new()
	root.clip_contents = true
	tile.add_child(root)

	if locked:
		var backdrop := ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0.13, 0.13, 0.15, 1.0)
		root.add_child(backdrop)

		var mystery := Label.new()
		mystery.text = "?"
		mystery.set_anchors_preset(Control.PRESET_FULL_RECT)
		mystery.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mystery.add_theme_font_size_override("font_size", 64)
		mystery.add_theme_color_override("font_color", Color(0.604, 0.561, 0.478, 0.9))
		root.add_child(mystery)
	else:
		# Character's stage bg behind, tinted toward the signature accent, with
		# the fighter framed as a bust on top — same layering as the big panels.
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture = _load_art(slot["id"], "bg")
		root.add_child(bg)

		var wash := ColorRect.new()
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.color = Color(accent, 0.32)
		root.add_child(wash)

		_add_bust_art(root, SLOT_SIZE, _load_art(slot["id"], "transparent"), 1.85, 0.28)

	# dark scrim so the name stays legible over busy art
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.offset_top = -52.0
	scrim.color = Color(0.047, 0.031, 0.024, 0.8)
	root.add_child(scrim)

	# number chip, top-left
	var chip := Label.new()
	chip.text = "%02d" % (index + 1)
	chip.position = Vector2(6, 6)
	chip.add_theme_font_override("font", BEBAS)
	chip.add_theme_font_size_override("font_size", 18)
	chip.add_theme_color_override("font_color", INK)
	chip.add_theme_stylebox_override("normal", _chip_stylebox(accent if not locked else MUTED))
	root.add_child(chip)

	# name
	var name_label := Label.new()
	name_label.text = slot["name"]
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -50.0
	name_label.offset_bottom = -18.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", BEBAS)
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", BONE)
	name_label.add_theme_color_override("font_outline_color", INK)
	name_label.add_theme_constant_override("outline_size", 6)
	root.add_child(name_label)

	# tag
	var tag_label := Label.new()
	tag_label.text = slot["tag"]
	tag_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag_label.offset_top = -18.0
	tag_label.offset_bottom = -3.0
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", 11)
	tag_label.add_theme_color_override("font_color", accent if not locked else MUTED)
	root.add_child(tag_label)

	_roster_strip.add_child(tile)
	return tile


func _chip_stylebox(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.set_border_width_all(2)
	sb.border_color = INK
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	sb.shadow_color = INK
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(2, 2)
	return sb


## Rebuilds one preview panel from that player's hovered slot + lock state:
## paired bg + character art (accent-washed), a giant vertical name, a P#
## READY/LOCKED corner badge, and a bottom info block (name + accent tag).
func _refresh_panel(player: int) -> void:
	var panel: PanelContainer = _p1_panel if player == 1 else _p2_panel
	var slot: Dictionary = _slots[_p1_slot if player == 1 else _p2_slot]
	var locked: bool = _p1_locked if player == 1 else _p2_locked
	var is_stub: bool = slot["locked"]
	var accent: Color = slot["color"]
	var badge_color: Color = accent if not is_stub else MUTED
	for child in panel.get_children():
		child.queue_free()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.clip_contents = true
	panel.add_child(root)

	if not is_stub:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.texture = _load_art(slot["id"], "bg")
		root.add_child(bg)

		# accent color wash over the bg
		var wash := ColorRect.new()
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.color = Color(accent, 0.16)
		root.add_child(wash)

		# Bust framing pushed toward the inner (VS) edge — P1 leans right, P2 left.
		_add_bust_art(root, panel.size, _load_art(slot["id"], "transparent"),
			1.5, 1.0 if player == 1 else -1.0)
	else:
		var backdrop := ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0.13, 0.13, 0.15, 1.0)
		root.add_child(backdrop)

		var mystery := Label.new()
		mystery.text = "?"
		mystery.set_anchors_preset(Control.PRESET_FULL_RECT)
		mystery.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mystery.add_theme_font_size_override("font_size", 140)
		mystery.add_theme_color_override("font_color", Color(0.604, 0.561, 0.478, 0.6))
		root.add_child(mystery)

	# bottom info block (fixed-height bar; root is a plain Control so anchors alone
	# would collapse a PanelContainer to zero height — reserve the rect explicitly)
	var info := PanelContainer.new()
	info.theme_type_variation = "PanelInfoBlock"
	info.anchor_left = 0.0
	info.anchor_right = 1.0
	info.anchor_top = 1.0
	info.anchor_bottom = 1.0
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_top = -122.0
	info.offset_bottom = 0.0
	info.add_theme_stylebox_override("panel", _info_stylebox(badge_color))
	root.add_child(info)

	# P1 reads left-aligned, P2 mirrors to the right.
	var align := HORIZONTAL_ALIGNMENT_LEFT if player == 1 else HORIZONTAL_ALIGNMENT_RIGHT

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	info.add_child(box)

	var name_label := Label.new()
	name_label.text = slot["name"]
	name_label.horizontal_alignment = align
	name_label.add_theme_font_override("font", BEBAS)
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", BONE)
	box.add_child(name_label)

	var tag_label := Label.new()
	tag_label.text = slot["tag"]
	tag_label.horizontal_alignment = align
	tag_label.add_theme_font_size_override("font_size", 14)
	tag_label.add_theme_color_override("font_color", badge_color)
	box.add_child(tag_label)

	var desc_label := Label.new()
	desc_label.text = LOCKED_DESC if is_stub else DESCRIPTIONS.get(slot["id"], GENERIC_DESC)
	desc_label.horizontal_alignment = align
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", MUTED)
	box.add_child(desc_label)

	# P# // READY|LOCKED corner badge
	var badge := Label.new()
	badge.text = "P%d  //  %s" % [player, "LOCKED" if locked else "READY"]
	badge.add_theme_font_override("font", BEBAS)
	badge.add_theme_font_size_override("font_size", 28)
	badge.add_theme_color_override("font_color", INK)
	badge.add_theme_stylebox_override("normal", _badge_stylebox(badge_color))
	badge.offset_top = 8.0
	if player == 1:
		badge.offset_left = 8.0
	else:
		badge.anchor_left = 1.0
		badge.anchor_right = 1.0
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = -8.0
	root.add_child(badge)


func _info_stylebox(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.047, 0.031, 0.024, 0.92)
	sb.border_width_top = 4
	sb.border_color = accent
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb


func _badge_stylebox(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	sb.set_border_width_all(3)
	sb.border_color = INK
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	sb.shadow_color = INK
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(5, 5)
	return sb


func _init_cursors() -> void:
	_update_cursor(_p1_cursor, _p1_slot)
	_update_cursor(_p2_cursor, _p2_slot)
	_update_status()
	_refresh_panel(1)
	_refresh_panel(2)


func _process(_delta: float) -> void:
	_handle_player(1)
	_handle_player(2)
	_maybe_advance()


func _handle_player(player: int) -> void:
	var locked: bool = _p1_locked if player == 1 else _p2_locked
	var slot: int = _p1_slot if player == 1 else _p2_slot

	if locked:
		if Input.is_action_just_pressed("p%d_heavy" % player):
			_set_locked(player, false)
		return

	if Input.is_action_just_pressed("p%d_left" % player):
		_set_slot(player, (slot - 1 + _slots.size()) % _slots.size())
	elif Input.is_action_just_pressed("p%d_right" % player):
		_set_slot(player, (slot + 1) % _slots.size())
	elif Input.is_action_just_pressed("p%d_fast" % player):
		if not _slots[slot]["locked"]:
			_set_locked(player, true)


func _set_slot(player: int, slot: int) -> void:
	if player == 1:
		_p1_slot = slot
		_update_cursor(_p1_cursor, slot)
	else:
		_p2_slot = slot
		_update_cursor(_p2_cursor, slot)
	_update_status()
	_refresh_panel(player)


func _set_locked(player: int, locked: bool) -> void:
	if player == 1:
		_p1_locked = locked
	else:
		_p2_locked = locked
	_update_status()
	_refresh_panel(player)


func _update_cursor(cursor: Control, slot: int) -> void:
	var node: Control = _slot_nodes[slot]
	var local_pos: Vector2 = node.get_global_rect().position - global_position
	cursor.position = local_pos - Vector2(CURSOR_MARGIN, CURSOR_MARGIN)
	cursor.size = node.get_global_rect().size + Vector2(CURSOR_MARGIN, CURSOR_MARGIN) * 2.0


func _update_status() -> void:
	_p1_status.text = "P1: %s%s" % [_slots[_p1_slot]["name"], "  [LOCKED]" if _p1_locked else ""]
	_p2_status.text = "P2: %s%s" % [_slots[_p2_slot]["name"], "  [LOCKED]" if _p2_locked else ""]


func _maybe_advance() -> void:
	if _advanced or not (_p1_locked and _p2_locked):
		return
	_advanced = true

	var p1: Dictionary = _slots[_p1_slot]
	var p2: Dictionary = _slots[_p2_slot]
	MatchSelection.p1_data = p1["data"]
	MatchSelection.p1_color = p1["color"]
	MatchSelection.p2_data = p2["data"]
	MatchSelection.p2_color = p2["color"]

	get_tree().change_scene_to_file("res://scenes/stage_select.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
