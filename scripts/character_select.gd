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

const SLOT_SIZE := Vector2(150, 170)
const CURSOR_MARGIN := 8.0

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
						"color": data.color, "data": data,
					})
			folder = dir.get_next()
		dir.list_dir_end()

	found.sort_custom(_by_roster_order)

	while found.size() < ROSTER_SIZE:
		found.append({"id": "", "locked": true, "name": "???", "color": LOCKED_COLOR, "data": null})
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
	var box := VBoxContainer.new()
	box.custom_minimum_size = SLOT_SIZE
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(SLOT_SIZE.x, 110)
	swatch.color = slot["color"]
	if slot["locked"]:
		swatch.color.a = 0.5
	box.add_child(swatch)

	var name_label := Label.new()
	name_label.text = slot["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)

	if slot["locked"]:
		var lock_label := Label.new()
		lock_label.text = "LOCKED"
		lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_label.add_theme_font_size_override("font_size", 14)
		lock_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1))
		box.add_child(lock_label)

	_slots_row.add_child(box)
	return box


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

	get_tree().change_scene_to_file("res://scenes/stage_select.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
