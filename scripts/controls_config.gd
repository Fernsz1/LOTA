extends Node
## Persists custom keyboard bindings for the remappable gameplay actions across
## sessions. InputMap changes are runtime-only in Godot, so rebinds are mirrored to
## user://controls.cfg and re-applied here on boot, before any scene reads input.
## Gamepad bindings are left untouched — only the keyboard event per action is replaced.

const SAVE_PATH := "user://controls.cfg"

const REMAPPABLE_ACTIONS: Array[String] = [
	"p1_left", "p1_right", "p1_up", "p1_down",
	"p1_fast", "p1_heavy", "p1_skill", "p1_ultimate",
	"p2_left", "p2_right", "p2_up", "p2_down",
	"p2_fast", "p2_heavy", "p2_skill", "p2_ultimate",
]


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for action in REMAPPABLE_ACTIONS:
		if cfg.has_section_key("input", action):
			_apply_keyboard_event(action, cfg.get_value("input", action))


## Erases the action's current keyboard event (gamepad events are untouched),
## binds the new physical keycode, and persists it to disk immediately.
func rebind(action: String, physical_keycode: int) -> void:
	_apply_keyboard_event(action, physical_keycode)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # missing file is fine — starts from an empty ConfigFile
	cfg.set_value("input", action, physical_keycode)
	cfg.save(SAVE_PATH)


## Human-readable label for the action's current keyboard binding ("—" if none).
func get_key_display(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev.as_text_physical_keycode()
	return "—"


func _apply_keyboard_event(action: String, physical_keycode: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var new_event := InputEventKey.new()
	new_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, new_event)
