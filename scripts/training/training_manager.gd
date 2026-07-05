class_name TrainingManager
extends Node
## 4.1 — Dummy AI, infinite-health overrides, and position reset for all 4 training chars.
## P1 and P2 are always human-controlled. P1Dummy (idx 3) and P2Dummy (idx 4) are always AI.
## Keys: R=reset  1/2=cycle P1/P2 dummy mode  3/4=dummy ♥INF  Q/E=player ♥INF  5=fill meters
## 7.5: the ult meter is the REAL versus rage bar (builds on damage dealt/taken,
## spent on activation) — key 5 refills both players instantly for practice.

enum DummyMode { STAND, CROUCH, JUMP }
const MODE_LABELS: Array[String] = ["STAND", "CROUCH", "JUMP"]

const P1_SPAWN_X: float = 250.0
const P1_DUMMY_SPAWN_X: float = 540.0
const P2_DUMMY_SPAWN_X: float = 740.0
const P2_SPAWN_X: float = 1030.0
const JUMP_CYCLE: int = 90      # frames between dummy jump inputs
const REGEN_DELAY: int = 300    # 5 s at 60 fps before regen starts
const REGEN_PER_FRAME: int = 9  # HP per frame once regen is active (~2 s to full)

@export var p1_path: NodePath
@export var p1_dummy_path: NodePath
@export var p2_dummy_path: NodePath
@export var p2_path: NodePath
@export var hud_path: NodePath

@onready var _p1: CharacterController = get_node(p1_path)
@onready var _p1_dummy: CharacterController = get_node(p1_dummy_path)
@onready var _p2_dummy: CharacterController = get_node(p2_dummy_path)
@onready var _p2: CharacterController = get_node(p2_path)
@onready var _hud: Node = get_node(hud_path)

var p1_dummy_mode: DummyMode = DummyMode.STAND
var p2_dummy_mode: DummyMode = DummyMode.STAND
var p1_infinite: bool = false
var p1_dummy_infinite: bool = false
var p2_dummy_infinite: bool = false
var p2_infinite: bool = false

var _p1_dummy_jump_timer: int = 0
var _p2_dummy_jump_timer: int = 0

var _p1d_prev_hp: int = CharacterController.MAX_HEALTH
var _p2d_prev_hp: int = CharacterController.MAX_HEALTH
var _p1d_regen_timer: int = 0
var _p2d_regen_timer: int = 0


func _ready() -> void:
	_push_status()
	# Initial spawn reset, deferred: set_character() (applied in the PARENT's
	# _ready, which runs after this one) swaps stats like max_health but keeps
	# the .tscn fighter's current health — versus fixes that via MatchManager's
	# immediate round reset, so training needs its own equivalent (7.5).
	call_deferred("reset_positions")


func _physics_process(_delta: float) -> void:
	if p1_infinite:       _p1.health = _p1.get_max_health()
	if p1_dummy_infinite: _p1_dummy.health = _p1_dummy.get_max_health()
	if p2_dummy_infinite: _p2_dummy.health = _p2_dummy.get_max_health()
	if p2_infinite:       _p2.health = _p2.get_max_health()
	# Drive dummies via virtual player slots (player_index 3 and 4)
	InputManager.set_override(3, _mode_bits(p1_dummy_mode, _p1_dummy_jump_timer))
	InputManager.set_override(4, _mode_bits(p2_dummy_mode, _p2_dummy_jump_timer))
	_p1_dummy_jump_timer = (_p1_dummy_jump_timer + 1) % JUMP_CYCLE
	_p2_dummy_jump_timer = (_p2_dummy_jump_timer + 1) % JUMP_CYCLE
	# Dummy health regen: 5 s delay, then ~2 s to full. Skipped if ♥INF active.
	if not p1_dummy_infinite:
		if _p1_dummy.health < _p1d_prev_hp:
			_p1d_regen_timer = 0
		elif _p1d_regen_timer < REGEN_DELAY:
			_p1d_regen_timer += 1
		else:
			_p1_dummy.health = mini(_p1_dummy.health + REGEN_PER_FRAME, _p1_dummy.get_max_health())
		_p1d_prev_hp = _p1_dummy.health
	if not p2_dummy_infinite:
		if _p2_dummy.health < _p2d_prev_hp:
			_p2d_regen_timer = 0
		elif _p2d_regen_timer < REGEN_DELAY:
			_p2d_regen_timer += 1
		else:
			_p2_dummy.health = mini(_p2_dummy.health + REGEN_PER_FRAME, _p2_dummy.get_max_health())
		_p2d_prev_hp = _p2_dummy.health


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_R:
			reset_positions()
		KEY_5:
			# Instant meter refill (players only — dummies never ult), so the
			# cinematic ultimates stay practicable without grinding the bar.
			_p1.fill_meter()
			_p2.fill_meter()
		KEY_1:
			p1_dummy_mode = wrapi(p1_dummy_mode + 1, 0, MODE_LABELS.size()) as DummyMode
		KEY_2:
			p2_dummy_mode = wrapi(p2_dummy_mode + 1, 0, MODE_LABELS.size()) as DummyMode
		KEY_3:
			p1_dummy_infinite = not p1_dummy_infinite
		KEY_4:
			p2_dummy_infinite = not p2_dummy_infinite
		KEY_Q:
			p1_infinite = not p1_infinite
		KEY_E:
			p2_infinite = not p2_infinite
		_:
			return
	_push_status()


func reset_positions() -> void:
	_p1.reset_for_round(P1_SPAWN_X)
	_p1_dummy.reset_for_round(P1_DUMMY_SPAWN_X)
	_p2_dummy.reset_for_round(P2_DUMMY_SPAWN_X)
	_p2.reset_for_round(P2_SPAWN_X)


# Status pushes are event-driven (toggles change rarely), not per-frame.
func _push_status() -> void:
	_hud.set_dummy_status(1, MODE_LABELS[p1_dummy_mode], p1_dummy_infinite)
	_hud.set_dummy_status(2, MODE_LABELS[p2_dummy_mode], p2_dummy_infinite)
	_hud.set_player_status(1, p1_infinite)
	_hud.set_player_status(2, p2_infinite)


func _mode_bits(mode: DummyMode, jump_timer: int) -> int:
	match mode:
		DummyMode.STAND:
			return 0
		DummyMode.CROUCH:
			return InputBuffer.DOWN
		DummyMode.JUMP:
			return InputBuffer.UP if jump_timer == 0 else 0
	return 0
