class_name CharacterController
extends Node2D
## Phase 1.4/1.5 — translates per-player InputBuffer into FSM transitions and applies
## frame-unit physics (px/frame — never delta). Pushbox separation and facing updates
## live in main.gd (_physics_process priority 1, runs after both controllers).

# --- Movement constants (px/frame or frames; tune at 3.6 GO/NO-GO) ---
const WALK_SPEED: float = 5.0
const WALK_B_SPEED: float = 4.5       # slower than walk forward
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
const PUSH_W: float = 40.0            # pushbox width — must match visual box width
const PUSH_H: float = 80.0            # pushbox height — must match visual box height

@export var player_index: int = 1
@export var facing: int = 1           # 1 = right, -1 = left
@export var box_color: Color = Color(1, 1, 1, 1)
@export var move_fast: MoveData       # 2.3 — light attack frame data (jab)
@export var move_heavy: MoveData      # 2.3 — heavy attack frame data (knockdown)
@export var move_skill: MoveData      # 3.1 — skill attack frame data
@export var move_ultimate: MoveData   # 3.1 — ultimate attack frame data

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

# --- Combat state (2.3–2.6) ---
const MAX_HEALTH: int = 1000
const ATTACK_BUFFER: int = 4          # frames of input buffer on attack press (feel-reference §4)
const KNOCKDOWN_FRAMES: int = 80      # time face-down before getup (2.5)
const GETUP_FRAMES: int = 16          # wake-up; invulnerable throughout (2.5)
const PUSHBACK_DECAY: float = 0.85    # per-frame pushback falloff (2.4 — blockstrings self-space)
var health: int = MAX_HEALTH
var _current_move: MoveData = null    # the move the active attack state is reading
var _move_has_hit: bool = false       # one hit per attack: cleared when a new attack starts
var _hitstop: int = 0                 # impact freeze; pauses everything incl. frame_in_state
var _stun_frames: int = 0             # length of the current HITSTUN/BLOCKSTUN
var _pushback_vel: float = 0.0        # px/frame applied during a reaction, decaying
var _projectile_spawned_this_move: bool = false   # 3.2: one projectile per attack
signal projectile_requested(data: ProjectileData, origin: Vector2, facing: int)

var _overlay: Node = null

@onready var _box: ColorRect = $Box


func setup(floor_y: float, left_x: float, right_x: float, overlay: Node) -> void:
	_floor_y = floor_y
	_left_x = left_x
	_right_x = right_x
	_overlay = overlay
	position.y = _floor_y


func _ready() -> void:
	_box.color = box_color
	# Validate frame data on load (conventions: validate with assert/push_error).
	if move_fast != null:
		move_fast.validate()
	if move_heavy != null:
		move_heavy.validate()
	# Tell Godot the scene-file position is the true starting point — prevents the
	# interpolator from visually sliding in from the origin on the first frame.
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	# Hitstop (2.4): freeze the whole character — input, movement, and frame_in_state —
	# so the impact freeze never counts as stun (feel-reference §4/§7).
	if _hitstop > 0:
		_hitstop -= 1
		return
	var buf: InputBuffer = InputManager.get_buffer(player_index)
	_resolve_busy_exits(buf)
	_process_input(buf)
	_resolve_attack()
	_resolve_projectile_spawn()
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
		CharacterStateMachine.State.FAST_ATTACK, CharacterStateMachine.State.HEAVY_ATTACK, \
		CharacterStateMachine.State.SKILL:
			# Locked through the move's full length (2.3); then actionable again.
			if _current_move == null or _fsm.frame_in_state >= _current_move.total():
				if position.y < _floor_y:
					_fsm.request(CharacterStateMachine.State.JUMP_AIR)
				else:
					_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.HITSTUN, CharacterStateMachine.State.BLOCKSTUN:
			if _fsm.frame_in_state >= _stun_frames:        # 2.4 stun length
				if position.y < _floor_y:
					_fsm.request(CharacterStateMachine.State.JUMP_AIR)
				else:
					_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.KNOCKDOWN:
			if _fsm.frame_in_state >= KNOCKDOWN_FRAMES and position.y >= _floor_y:
				_fsm.request(CharacterStateMachine.State.GETUP)
		CharacterStateMachine.State.GETUP:
			if _fsm.frame_in_state >= GETUP_FRAMES:         # 2.5 (invuln window)
				_fsm.request(CharacterStateMachine.State.IDLE)


# Translate held/pressed bits from the buffer into FSM requests.
# Double-tap timers advance every frame; FSM requests only fire when actionable.
func _process_input(buf: InputBuffer) -> void:
	var fwd_bit: int = InputBuffer.RIGHT if facing > 0 else InputBuffer.LEFT
	var bwd_bit: int = InputBuffer.LEFT if facing > 0 else InputBuffer.RIGHT

	var fwd_held: bool = buf.is_held(fwd_bit)
	var bwd_held: bool = buf.is_held(bwd_bit)
	var down_held: bool = buf.is_held(InputBuffer.DOWN)
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

	# Attacks (2.3) — buffered presses, checked while actionable. Priority: Ultimate > Heavy > Skill > Fast.
	# On a successful start, arm the move and clear the one-hit latch.
	# NOTE: Treating ultimate as a second SKILL slot to avoid changing FSM structure (Phase 3.1 constraint).
	if move_ultimate != null and buf.pressed_within(InputBuffer.ULTIMATE, ATTACK_BUFFER) \
			and _fsm.request(CharacterStateMachine.State.SKILL):
		_arm(move_ultimate)
		return
	if move_heavy != null and buf.pressed_within(InputBuffer.HEAVY, ATTACK_BUFFER) \
			and _fsm.request(CharacterStateMachine.State.HEAVY_ATTACK):
		_arm(move_heavy)
		return
	if move_skill != null and buf.pressed_within(InputBuffer.SKILL, ATTACK_BUFFER) \
			and _fsm.request(CharacterStateMachine.State.SKILL):
		# TODO(3.5): skill.tres is currently a single 120-damage hit. Multi-hit behavior
		# (3 hits) will need the cancel system (3.5) to chain properly.
		_arm(move_skill)
		return
	if move_fast != null and buf.pressed_within(InputBuffer.FAST, ATTACK_BUFFER) \
			and _fsm.request(CharacterStateMachine.State.FAST_ATTACK):
		_arm(move_fast)
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

	# Blocking is hold-back (2.4): holding away yields WALK_B / CROUCH (both block-capable),
	# and the guard is resolved at hit-time by HitResolver — no dedicated block input.

	# Normal ground movement (4-frame action buffer on jump).
	if buf.pressed_within(InputBuffer.UP, 4):
		_fsm.request(CharacterStateMachine.State.JUMP_START)
	elif down_held:
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
			_vel.x = -WALK_B_SPEED * facing
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
		CharacterStateMachine.State.HITSTUN, CharacterStateMachine.State.BLOCKSTUN:
			# Pushback (2.4): slide away from the attacker, decaying
			_vel.x = _pushback_vel
			if position.y < _floor_y:
				_vel.y += GRAVITY
			else:
				_vel.y = 0.0
			_pushback_vel *= PUSHBACK_DECAY
		CharacterStateMachine.State.KNOCKDOWN:
			if position.y < _floor_y:
				_vel.y += GRAVITY
			else:
				_vel.y = 0.0
			_vel.x = 0.0
		_:
			# IDLE, CROUCH, BLOCK, JUMP_START, JUMP_LAND, GETUP — no lateral movement.
			_vel.x = 0.0

	position += _vel

	# Land when airborne and at or past the floor.
	if CharacterStateMachine.is_airborne(_fsm.state) and position.y >= _floor_y:
		position.y = _floor_y
		_vel = Vector2.ZERO
		_fsm.request(CharacterStateMachine.State.JUMP_LAND)
	else:
		position.y = minf(position.y, _floor_y)

	# Keep the character fully inside stage walls (centre ± half-width).
	position.x = clampf(position.x, _left_x + PUSH_W * 0.5, _right_x - PUSH_W * 0.5)


## World-space pushbox for 1.5 separation. X-only overlap is checked by main.gd.
func get_pushbox() -> Rect2:
	return Rect2(position.x - PUSH_W * 0.5, position.y - PUSH_H, PUSH_W, PUSH_H)


# --- Combat boxes (2.1) — local, facing-right; origin at feet (bottom-centre) ---
const HURTBOX_STAND: Rect2 = Rect2(-20, -80, 40, 80)   # matches the visual Box
const HURTBOX_CROUCH: Rect2 = Rect2(-20, -52, 40, 52)  # shorter while crouching

# Live hitboxes in local space. Empty in the common case → overlap checks stay cheap.
# Set by the attack state in 2.3; until then the TEMP block below drives a test box.
var active_hitboxes_local: Array[Rect2] = []

## World-space hurtbox set for the current stance (one box in v1; multi-box bodies later).
func get_hurtboxes() -> Array[Rect2]:
	var local: Rect2 = HURTBOX_CROUCH if _fsm.state == CharacterStateMachine.State.CROUCH \
		else HURTBOX_STAND
	return [CombatBoxes.to_world(local, position, facing)]

## World-space active hitboxes — empty when not attacking (cheap early-out for callers).
func get_hitboxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for h in active_hitboxes_local:
		out.append(CombatBoxes.to_world(h, position, facing))
	return out


func _update_debug() -> void:
	if _overlay == null:
		return
	_overlay.set_state(player_index, CharacterStateMachine.State.keys()[_fsm.state])


# --- Attack hitboxes (2.3) — driven by the current move's frame data ---
# Live only on the move's active frames (MoveData.hitboxes_at); empty otherwise so
# overlap checks stay cheap. Replaces the 2.1 temp test driver.
func _resolve_attack() -> void:
	if _current_move != null and CharacterStateMachine.is_attacking(_fsm.state):
		active_hitboxes_local = _current_move.hitboxes_at(_fsm.frame_in_state)
	else:
		active_hitboxes_local = []


## Arm a freshly-started attack: set the move and clear per-attack latches.
func _arm(move: MoveData) -> void:
	_current_move = move
	_move_has_hit = false
	_projectile_spawned_this_move = false


## 3.2 — emit a spawn request on the move's projectile_spawn_at() frame, once.
func _resolve_projectile_spawn() -> void:
	if _current_move == null or _current_move.projectile == null:
		return
	if not CharacterStateMachine.is_attacking(_fsm.state):
		return
	if _projectile_spawned_this_move:
		return
	if _fsm.frame_in_state == _current_move.projectile_spawn_at():
		var off: Vector2 = _current_move.projectile.spawn_offset
		var origin: Vector2 = position + Vector2(off.x * facing, off.y)
		projectile_requested.emit(_current_move.projectile, origin, facing)
		_projectile_spawned_this_move = true


# --- Combat public API (2.4–2.6) — called by main.gd hit resolution / match manager ---

func fsm_state() -> int:
	return _fsm.state

## Frozen during hitstop — main.gd skips resolution while either fighter is frozen.
func is_frozen() -> bool:
	return _hitstop > 0

## Invulnerable on wake-up (GETUP) and when KO'd — hits pass through.
func is_invulnerable() -> bool:
	return _fsm.state == CharacterStateMachine.State.GETUP \
		or _fsm.state == CharacterStateMachine.State.KO

## True while holding the away-from-opponent direction (the block input, 2.4).
func is_holding_back() -> bool:
	var buf: InputBuffer = InputManager.get_buffer(player_index)
	var bwd_bit: int = InputBuffer.LEFT if facing > 0 else InputBuffer.RIGHT
	return buf.is_held(bwd_bit)

## The move whose hitbox can currently connect (null if none / already hit this attack).
func get_active_move() -> MoveData:
	if _move_has_hit or _current_move == null:
		return null
	if not CharacterStateMachine.is_attacking(_fsm.state):
		return null
	if active_hitboxes_local.is_empty():
		return null
	return _current_move

## Latch so one attack lands at most one hit (survives the hitstop freeze, 2.4).
func mark_move_hit() -> void:
	_move_has_hit = true

func apply_hitstop(frames: int) -> void:
	_hitstop = frames

## Resolve a clean hit (2.4) — damage, pushback, and HITSTUN (or KNOCKDOWN on a
## launcher / airborne hit, 2.5). push_dir is +1/-1 away from the attacker.
func apply_hit(move: MoveData, push_dir: float) -> void:
	health = maxi(0, health - move.damage)
	_stun_frames = move.hitstun
	_pushback_vel = move.pushback_hit * push_dir
	if move.causes_knockdown:
		_fsm.on_launched()   # → KNOCKDOWN
	else:
		_fsm.on_hit()        # → HITSTUN

## Resolve a blocked hit (2.4) — no damage (no chip in v1), BLOCKSTUN, more pushback.
func apply_block(move: MoveData, push_dir: float) -> void:
	_stun_frames = move.blockstun
	_pushback_vel = move.pushback_block * push_dir
	_fsm.on_blocked()        # → BLOCKSTUN

## Resolve a projectile clean hit (3.2) — same effect as apply_hit, ProjectileData payload.
func apply_hit_proj(data: ProjectileData, push_dir: float) -> void:
	health = maxi(0, health - data.damage)
	_stun_frames = data.hitstun
	_pushback_vel = data.pushback_hit * push_dir
	if data.causes_knockdown:
		_fsm.on_launched()
	else:
		_fsm.on_hit()

## Resolve a blocked projectile (3.2) — no damage, blockstun, more pushback.
func apply_block_proj(data: ProjectileData, push_dir: float) -> void:
	_stun_frames = data.blockstun
	_pushback_vel = data.pushback_block * push_dir
	_fsm.on_blocked()

## Force the KO state on the round loser (2.6).
func force_ko() -> void:
	_fsm.on_ko()

## Reset everything for a fresh round (2.6).
func reset_for_round(spawn_x: float) -> void:
	position = Vector2(spawn_x, _floor_y)
	health = MAX_HEALTH
	_vel = Vector2.ZERO
	_hitstop = 0
	_stun_frames = 0
	_pushback_vel = 0.0
	_current_move = null
	_move_has_hit = false
	_projectile_spawned_this_move = false
	active_hitboxes_local = []
	_fsm.reset(CharacterStateMachine.State.IDLE)
	reset_physics_interpolation()
