class_name CharacterController
extends Node2D
## Phase 1.4 — translates per-player InputBuffer into FSM transitions and applies
## frame-unit physics (px/frame — never delta). Stage bounds and player-vs-player
## pushboxes are added in 1.5.

# --- Movement constants (px/frame or frames; tune at 3.6 GO/NO-GO) ---
const WALK_SPEED: float = 5.0
const JUMP_VELOCITY: float = -13.0    # up is negative in Godot 2D
const GRAVITY: float = 0.565          # → ~46-frame airtime (feel-reference §5)
const JUMP_F_SPEED: float = 3.5       # horizontal speed on forward/back jump
const JUMPSQUAT_FRAMES: int = 2       # 4 in final (feel-reference §5); 2 for early testing
const JUMP_LAND_FRAMES: int = 3       # feel-reference §5
const DASH_SPEED: float = 9.0
const DASH_TOTAL: int = 16
const BACKDASH_SPEED: float = 7.0     # applied in -facing direction
const BACKDASH_TOTAL: int = 20        # feel-reference §5
const DOUBLE_TAP_WINDOW: int = 8      # frames between two directional taps → dash

@export var player_index: int = 1
@export var facing: int = 1           # 1 = right, -1 = left
@export var box_color: Color = Color(1, 1, 1, 1)

var _fsm: CharacterStateMachine = CharacterStateMachine.new()
var _vel: Vector2 = Vector2.ZERO
var _floor_y: float = 540.0
var _left_x: float = 50.0
var _right_x: float = 1230.0

# Double-tap state (tracked every frame, regardless of actionability)
var _fwd_tap_timer: int = 999
var _bwd_tap_timer: int = 999
var _prev_fwd: bool = false
var _prev_bwd: bool = false

var _overlay: Node = null

@onready var _box: ColorRect = $Box


func setup(floor_y: float, left_x: float, right_x: float, overlay: Node) -> void:
	_floor_y = floor_y
	_left_x = left_x
	_right_x = right_x
	_overlay = overlay


func _ready() -> void:
	_box.color = box_color
	# Tell Godot the scene-file position is the true starting point — prevents the
	# interpolator from visually sliding in from the origin on the first frame.
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	var buf: InputBuffer = InputManager.get_buffer(player_index)
	_resolve_busy_exits(buf)
	_process_input(buf)
	_apply_movement()
	_update_debug()
	_fsm.tick()


# Busy states that exit on frame count: JUMP_START → air, JUMP_LAND → IDLE,
# DASH/BACKDASH → IDLE. Called before input so the new state is seen immediately.
func _resolve_busy_exits(buf: InputBuffer) -> void:
	match _fsm.state:
		CharacterStateMachine.State.JUMP_START:
			if _fsm.frame_in_state >= JUMPSQUAT_FRAMES:
				var fwd_bit: int = InputBuffer.RIGHT if facing > 0 else InputBuffer.LEFT
				var bwd_bit: int = InputBuffer.LEFT if facing > 0 else InputBuffer.RIGHT
				if buf.is_held(fwd_bit):
					_fsm.request(CharacterStateMachine.State.JUMP_F)
					_vel.x = JUMP_F_SPEED * facing
				elif buf.is_held(bwd_bit):
					_fsm.request(CharacterStateMachine.State.JUMP_B)
					_vel.x = -JUMP_F_SPEED * facing
				else:
					_fsm.request(CharacterStateMachine.State.JUMP_AIR)
					_vel.x = 0.0
				_vel.y = JUMP_VELOCITY
		CharacterStateMachine.State.JUMP_LAND:
			if _fsm.frame_in_state >= JUMP_LAND_FRAMES:
				_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.DASH:
			if _fsm.frame_in_state >= DASH_TOTAL:
				_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.BACKDASH:
			if _fsm.frame_in_state >= BACKDASH_TOTAL:
				_fsm.request(CharacterStateMachine.State.IDLE)


# Translate held/pressed bits from the buffer into FSM requests.
# Double-tap timers advance every frame; FSM requests only fire when actionable.
func _process_input(buf: InputBuffer) -> void:
	var fwd_bit: int = InputBuffer.RIGHT if facing > 0 else InputBuffer.LEFT
	var bwd_bit: int = InputBuffer.LEFT if facing > 0 else InputBuffer.RIGHT

	var fwd_held: bool = buf.is_held(fwd_bit)
	var bwd_held: bool = buf.is_held(bwd_bit)
	var fwd_rising: bool = fwd_held and not _prev_fwd
	var bwd_rising: bool = bwd_held and not _prev_bwd
	_prev_fwd = fwd_held
	_prev_bwd = bwd_held

	if _fwd_tap_timer < 999:
		_fwd_tap_timer += 1
	if _bwd_tap_timer < 999:
		_bwd_tap_timer += 1

	# Air control: steer horizontal velocity while airborne without changing FSM state.
	if CharacterStateMachine.is_airborne(_fsm.state):
		if fwd_held:
			_vel.x = JUMP_F_SPEED * facing
		elif bwd_held:
			_vel.x = -JUMP_F_SPEED * facing
		else:
			_vel.x = 0.0
		return

	if not CharacterStateMachine.is_actionable(_fsm.state):
		return

	# Double-tap check — fires before single-direction walk so a second tap dashes.
	if fwd_rising:
		if _fwd_tap_timer <= DOUBLE_TAP_WINDOW and _fsm.request(CharacterStateMachine.State.DASH):
			_fwd_tap_timer = 999
			return
		_fwd_tap_timer = 0

	if bwd_rising:
		if _bwd_tap_timer <= DOUBLE_TAP_WINDOW and _fsm.request(CharacterStateMachine.State.BACKDASH):
			_bwd_tap_timer = 999
			return
		_bwd_tap_timer = 0

	# Normal ground movement (4-frame action buffer on jump).
	if buf.pressed_within(InputBuffer.UP, 4):
		_fsm.request(CharacterStateMachine.State.JUMP_START)
	elif buf.is_held(InputBuffer.DOWN):
		_fsm.request(CharacterStateMachine.State.CROUCH)
	elif fwd_held:
		_fsm.request(CharacterStateMachine.State.WALK_F)
	elif bwd_held:
		_fsm.request(CharacterStateMachine.State.WALK_B)
	else:
		_fsm.request(CharacterStateMachine.State.IDLE)


# Apply per-frame velocity based on FSM state, then move, clamp to stage.
# Horizontal vel is set here for walk/dash; jump vel is set in _resolve_busy_exits.
func _apply_movement() -> void:
	match _fsm.state:
		CharacterStateMachine.State.WALK_F:
			_vel.x = WALK_SPEED * facing
			_vel.y = 0.0
		CharacterStateMachine.State.WALK_B:
			_vel.x = -WALK_SPEED * facing
			_vel.y = 0.0
		CharacterStateMachine.State.DASH:
			_vel.x = DASH_SPEED * facing
			_vel.y = 0.0
		CharacterStateMachine.State.BACKDASH:
			_vel.x = -BACKDASH_SPEED * facing
			_vel.y = 0.0
		CharacterStateMachine.State.JUMP_AIR, CharacterStateMachine.State.JUMP_F, \
		CharacterStateMachine.State.JUMP_B:
			_vel.y += GRAVITY   # horizontal vel preserved from jump launch
		_:
			# IDLE, CROUCH, BLOCK, JUMP_START, JUMP_LAND, reactions — no lateral movement.
			_vel.x = 0.0

	position += _vel

	# Land when airborne and at or past the floor.
	if CharacterStateMachine.is_airborne(_fsm.state) and position.y >= _floor_y:
		position.y = _floor_y
		_vel = Vector2.ZERO
		_fsm.request(CharacterStateMachine.State.JUMP_LAND)
	else:
		position.y = minf(position.y, _floor_y)

	position.x = clampf(position.x, _left_x, _right_x)


func _update_debug() -> void:
	if _overlay == null:
		return
	_overlay.set_state(player_index, CharacterStateMachine.State.keys()[_fsm.state])
