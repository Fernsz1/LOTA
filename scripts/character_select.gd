extends Control
## Tekken-style select screen. Both players share one grid; each moves their own
## cursor with p{n}_left/right, locks in with p{n}_fast, and unlocks with p{n}_heavy.
## Jerb/Rainne/Jacob are playable — the other 2 slots are locked stubs. Once both
## players are locked, their picks go to MatchSelection and we move on to loading.

const SLOTS: Array[Dictionary] = [
	{"id": "jerb", "name": "JERB", "locked": false, "data_path": "res://characters/jerb/jerb_data.tres", "color": Color(0.2, 0.5, 0.9, 1)},
	{"id": "rainne", "name": "RAINNE", "locked": false, "data_path": "res://characters/rainne/rainne_data.tres", "color": Color(0.9, 0.55, 0.15, 1)},
	{"id": "jacob", "name": "JACOB", "locked": false, "data_path": "res://characters/jacob/jacob_data.tres", "color": Color(0.62, 0.16, 0.18, 1)},
	{"id": "locked_1", "name": "???", "locked": true, "data_path": "", "color": Color(0.22, 0.22, 0.25, 1)},
	{"id": "locked_2", "name": "???", "locked": true, "data_path": "", "color": Color(0.22, 0.22, 0.25, 1)},
]

const SLOT_SIZE := Vector2(150, 170)
const CURSOR_MARGIN := 8.0

@onready var _slots_row: HBoxContainer = $CenterContainer/SlotsRow
@onready var _p1_cursor: Control = $P1Cursor
@onready var _p2_cursor: Control = $P2Cursor
@onready var _p1_status: Label = $StatusRow/P1Status
@onready var _p2_status: Label = $StatusRow/P2Status

var _slot_nodes: Array[Control] = []
var _p1_slot: int = 0
var _p2_slot: int = 1
var _p1_locked: bool = false
var _p2_locked: bool = false
var _advanced: bool = false


func _ready() -> void:
	for slot: Dictionary in SLOTS:
		_slot_nodes.append(_build_slot(slot))
	# Container layout resolves at end-of-frame; positioning cursors now would read
	# stale (zero) rects, so defer until the row has actually been sorted.
	call_deferred("_init_cursors")


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
		_set_slot(player, (slot - 1 + SLOTS.size()) % SLOTS.size())
	elif Input.is_action_just_pressed("p%d_right" % player):
		_set_slot(player, (slot + 1) % SLOTS.size())
	elif Input.is_action_just_pressed("p%d_fast" % player):
		if not SLOTS[slot]["locked"]:
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
	_p1_status.text = "P1: %s%s" % [SLOTS[_p1_slot]["name"], "  [LOCKED]" if _p1_locked else ""]
	_p2_status.text = "P2: %s%s" % [SLOTS[_p2_slot]["name"], "  [LOCKED]" if _p2_locked else ""]


func _maybe_advance() -> void:
	if _advanced or not (_p1_locked and _p2_locked):
		return
	_advanced = true

	var p1: Dictionary = SLOTS[_p1_slot]
	var p2: Dictionary = SLOTS[_p2_slot]
	MatchSelection.p1_data = load(p1["data_path"])
	MatchSelection.p1_color = p1["color"]
	MatchSelection.p2_data = load(p2["data_path"])
	MatchSelection.p2_color = p2["color"]

	get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
