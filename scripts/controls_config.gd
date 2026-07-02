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

## Shipped keyboard bindings (project.godot [input]) — the "factory reset" target.
const DEFAULT_KEYS: Dictionary = {
	"p1_left": KEY_A, "p1_right": KEY_D, "p1_up": KEY_W, "p1_down": KEY_S,
	"p1_fast": KEY_C, "p1_heavy": KEY_V, "p1_skill": KEY_B, "p1_ultimate": KEY_F,
	"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_up": KEY_UP, "p2_down": KEY_DOWN,
	"p2_fast": KEY_J, "p2_heavy": KEY_K, "p2_skill": KEY_L, "p2_ultimate": KEY_I,
}


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


## Restores every remappable action to its shipped keyboard binding and wipes the
## saved overrides file so the reset actually sticks across restarts.
func reset_to_defaults() -> void:
	for action in REMAPPABLE_ACTIONS:
		_apply_keyboard_event(action, DEFAULT_KEYS[action])
	var cfg := ConfigFile.new()
	cfg.save(SAVE_PATH)  # empty file — no overrides left to reapply on next boot


## Name of whichever OTHER remappable action already owns this physical keycode,
## or "" if it's free. Checked across both players (they share one keyboard), so a
## single key can never end up firing two actions at once. Excludes exclude_action
## itself so re-picking a row's own current key isn't flagged as a conflict.
func find_conflict(physical_keycode: int, exclude_action: String = "") -> String:
	for action in REMAPPABLE_ACTIONS:
		if action == exclude_action:
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and ev.physical_keycode == physical_keycode:
				return action
	return ""


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
