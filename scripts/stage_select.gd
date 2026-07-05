extends Control
## 7.2 — stage select. A shared, single-cursor pick (unlike character select, the
## stage isn't per-player) — either player's left/right moves it, either player's
## fast attack confirms. Data-driven the same way as character_select: every
## folder under stages/ with a matching <id>/<id>_data.tres is auto-discovered.

const STAGES_DIR := "res://stages/"
const SLOT_SIZE := Vector2(150, 170)
const CURSOR_MARGIN := 8.0

@onready var _slots_row: HBoxContainer = $CenterContainer/SlotsRow
@onready var _cursor: Control = $Cursor
@onready var _status: Label = $StatusLabel

var _stages: Array[Dictionary] = []
var _slot_nodes: Array[Control] = []
var _slot: int = 0
var _advanced: bool = false


func _ready() -> void:
	_stages = _build_stage_list()
	for stage: Dictionary in _stages:
		_slot_nodes.append(_build_slot(stage))
	call_deferred("_init_cursor")


func _build_stage_list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := DirAccess.open(STAGES_DIR)
	if dir:
		dir.list_dir_begin()
		var folder := dir.get_next()
		while folder != "":
			if dir.current_is_dir():
				var path := "%s%s/%s_data.tres" % [STAGES_DIR, folder, folder]
				if ResourceLoader.exists(path):
					var data: StageData = load(path)
					found.append({"name": data.stage_name.to_upper(), "data": data})
			folder = dir.get_next()
		dir.list_dir_end()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"])
	return found


func _build_slot(stage: Dictionary) -> Control:
	var data: StageData = stage["data"]
	var box := VBoxContainer.new()
	box.custom_minimum_size = SLOT_SIZE
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(SLOT_SIZE.x, 90)
	swatch.color = data.background_color
	box.add_child(swatch)

	var floor_swatch := ColorRect.new()
	floor_swatch.custom_minimum_size = Vector2(SLOT_SIZE.x, 20)
	floor_swatch.color = data.floor_color
	box.add_child(floor_swatch)

	var name_label := Label.new()
	name_label.text = stage["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	box.add_child(name_label)

	_slots_row.add_child(box)
	return box


func _init_cursor() -> void:
	_update_cursor()
	_update_status()


func _process(_delta: float) -> void:
	if _stages.is_empty() or _advanced:
		return
	if Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p2_left"):
		_set_slot((_slot - 1 + _stages.size()) % _stages.size())
	elif Input.is_action_just_pressed("p1_right") or Input.is_action_just_pressed("p2_right"):
		_set_slot((_slot + 1) % _stages.size())
	elif Input.is_action_just_pressed("p1_fast") or Input.is_action_just_pressed("p2_fast"):
		_confirm()


func _set_slot(slot: int) -> void:
	_slot = slot
	_update_cursor()
	_update_status()


func _update_cursor() -> void:
	var node: Control = _slot_nodes[_slot]
	var local_pos: Vector2 = node.get_global_rect().position - global_position
	_cursor.position = local_pos - Vector2(CURSOR_MARGIN, CURSOR_MARGIN)
	_cursor.size = node.get_global_rect().size + Vector2(CURSOR_MARGIN, CURSOR_MARGIN) * 2.0


func _update_status() -> void:
	_status.text = "STAGE: %s" % _stages[_slot]["name"]


func _confirm() -> void:
	_advanced = true
	MatchSelection.stage_data = _stages[_slot]["data"]
	# 7.5 — training entered this flow from the TRAINING menu item: cut
	# straight to the training scene (no loading screen / intro card).
	if MatchSelection.training:
		get_tree().change_scene_to_file("res://scenes/training.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")
