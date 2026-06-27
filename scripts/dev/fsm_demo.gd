extends Node2D
## THROWAWAY 1.3-local demo. Auto-drives a CharacterStateMachine through a scripted
## sequence inside _physics_process (proving the FSM ticks/transitions at 60 Hz in a
## live Godot scene), printing each transition and showing state on screen. Verified
## via the Godot MCP (run_project + get_debug_output). Deleted/replaced when the real
## 1.1 debug overlay + 1.2 input land in 1.4.

const CSM := preload("res://scripts/fsm/character_state_machine.gd")

# Demo-only fake durations (frames). The real FSM is duration-agnostic; these only
# pace the visualization so each transient state is visible before it resolves.
const DUR := {
	CSM.State.JUMP_START: 4,
	CSM.State.JUMP_AIR: 24, CSM.State.JUMP_F: 24, CSM.State.JUMP_B: 24,
	CSM.State.JUMP_LAND: 4,
	CSM.State.DASH: 12, CSM.State.BACKDASH: 14,
	CSM.State.FAST_ATTACK: 8, CSM.State.HEAVY_ATTACK: 16, CSM.State.SKILL: 22,
	CSM.State.HITSTUN: 14, CSM.State.BLOCKSTUN: 9, CSM.State.KNOCKDOWN: 40,
	CSM.State.GETUP: 12,
}

const HOLD := 18  # frames to linger in each actionable/settled state before next step

# Scripted steps, applied only when the machine is settled (actionable, or KO for reset).
var _steps := [
	{"op": "request", "to": CSM.State.WALK_F},
	{"op": "request", "to": CSM.State.WALK_B},
	{"op": "request", "to": CSM.State.CROUCH},
	{"op": "request", "to": CSM.State.IDLE},
	{"op": "request", "to": CSM.State.DASH},
	{"op": "request", "to": CSM.State.BACKDASH},
	{"op": "request", "to": CSM.State.JUMP_START},
	{"op": "request", "to": CSM.State.FAST_ATTACK},
	{"op": "request", "to": CSM.State.HEAVY_ATTACK},
	{"op": "request", "to": CSM.State.SKILL},
	{"op": "request", "to": CSM.State.BLOCK},
	{"op": "request", "to": CSM.State.IDLE},
	{"op": "force", "to": CSM.State.HITSTUN},
	{"op": "force", "to": CSM.State.BLOCKSTUN},
	{"op": "force", "to": CSM.State.KNOCKDOWN},
	{"op": "force", "to": CSM.State.KO},
	{"op": "reset", "to": CSM.State.IDLE},
]

var _sm: CSM
var _idx := 0
var _settle := 0
var _label: Label
var _box: ColorRect


func _ready() -> void:
	_label = $Label
	_box = $Box
	_sm = CSM.new()
	_sm.state_changed.connect(_on_state_changed)
	print("=== FSM DEMO START ===")


func _physics_process(_delta: float) -> void:
	_auto_resolve()
	if _settle > 0:
		_settle -= 1
	elif _idx < _steps.size() and _ready_for_next():
		_apply(_steps[_idx])
		_idx += 1
		_settle = HOLD
	elif _idx >= _steps.size():
		print("=== FSM DEMO COMPLETE (looping) ===")
		_idx = 0
		_settle = HOLD
	_update_visual()
	_sm.tick()


# Advance any timed/transient state back toward an actionable state.
func _auto_resolve() -> void:
	var s: int = _sm.state
	if not DUR.has(s):
		return
	if _sm.frame_in_state < DUR[s]:
		return
	_sm.request(_exit_of(s))


func _exit_of(s: int) -> int:
	match s:
		CSM.State.JUMP_START:
			return CSM.State.JUMP_AIR
		CSM.State.JUMP_AIR, CSM.State.JUMP_F, CSM.State.JUMP_B:
			return CSM.State.JUMP_LAND
		CSM.State.KNOCKDOWN:
			return CSM.State.GETUP
		_:
			return CSM.State.IDLE


func _ready_for_next() -> bool:
	if _steps[_idx]["op"] == "reset":
		return _sm.state == CSM.State.KO
	return CSM.is_actionable(_sm.state)


func _apply(step: Dictionary) -> void:
	match step["op"]:
		"request":
			_sm.request(step["to"])
		"force":
			_sm.force(step["to"])
		"reset":
			_sm.reset(step["to"])


func _update_visual() -> void:
	_label.text = "%s   f=%d   (prev %s)" % [
		_name(_sm.state), _sm.frame_in_state, _name(_sm.prev_state)]
	_box.color = _category_color(_sm.state)


func _category_color(s: int) -> Color:
	if CSM.is_ko(s):
		return Color(0.15, 0.15, 0.15)
	if CSM.is_in_reaction(s):
		return Color(0.85, 0.2, 0.2)
	if CSM.is_attacking(s):
		return Color(0.95, 0.75, 0.1)
	if CSM.is_airborne(s):
		return Color(0.3, 0.6, 0.95)
	if CSM.is_busy(s):
		return Color(0.6, 0.4, 0.8)
	return Color(0.85, 0.85, 0.85)  # actionable


func _on_state_changed(from: int, to: int) -> void:
	print("frame %d:  %s -> %s" % [Engine.get_physics_frames(), _name(from), _name(to)])


func _name(s: int) -> String:
	return CSM.State.keys()[s]
