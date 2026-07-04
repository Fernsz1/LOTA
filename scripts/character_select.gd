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

const SLOT_SIZE := Vector2(190, 260)
const PORTRAIT_HEIGHT := 180.0
const CURSOR_MARGIN := 8.0

const FIGHTER_SILHOUETTE := preload("res://art/ui/silhouettes/fighter.svg")

@onready var _slots_row: HBoxContainer = $CenterContainer/SlotsRow
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


func _ready() -> void:
	_slots = _build_roster()
	for slot: Dictionary in _slots:
		_slot_nodes.append(_build_slot(slot))
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


func _build_slot(slot: Dictionary) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = SLOT_SIZE
	tile.theme_type_variation = "CharacterTileLocked" if slot["locked"] else "CharacterTile"

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	tile.add_child(box)

	box.add_child(_build_portrait(slot))

	var name_label := Label.new()
	name_label.text = slot["name"]
	name_label.theme_type_variation = "TileNameLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)

	var tag_label := Label.new()
	tag_label.text = slot["tag"]
	tag_label.theme_type_variation = "TagLabel"
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not slot["locked"]:
		tag_label.add_theme_color_override("font_color", slot["color"])
	box.add_child(tag_label)

	_slots_row.add_child(tile)
	return tile


## Characters are intentionally undesigned: the portrait is a shared dark
## silhouette tinted toward the fighter's accent color over an accent gradient.
func _build_portrait(slot: Dictionary) -> Control:
	var accent: Color = slot["color"]
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(0, PORTRAIT_HEIGHT)

	var backdrop := TextureRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.texture = _make_backdrop_texture(accent)
	portrait.add_child(backdrop)

	var silhouette := TextureRect.new()
	silhouette.set_anchors_preset(Control.PRESET_FULL_RECT)
	silhouette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.texture = FIGHTER_SILHOUETTE
	if slot["locked"]:
		silhouette.modulate = Color(0.35, 0.35, 0.4, 0.4)
	else:
		silhouette.modulate = accent.lerp(Color.BLACK, 0.7)
	portrait.add_child(silhouette)

	if slot["locked"]:
		var mystery := Label.new()
		mystery.text = "?"
		mystery.set_anchors_preset(Control.PRESET_FULL_RECT)
		mystery.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mystery.add_theme_font_size_override("font_size", 64)
		mystery.add_theme_color_override("font_color", Color(0.604, 0.561, 0.478, 0.9))
		portrait.add_child(mystery)

	return portrait


func _make_backdrop_texture(accent: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(accent, 0.35), Color(accent, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture


func _init_cursors() -> void:
	_update_cursor(_p1_cursor, _p1_slot)
	_update_cursor(_p2_cursor, _p2_slot)
	_update_status()


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


func _set_locked(player: int, locked: bool) -> void:
	if player == 1:
		_p1_locked = locked
	else:
		_p2_locked = locked
	_update_status()


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

	get_tree().change_scene_to_file("res://scenes/map_select.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
