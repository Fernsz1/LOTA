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
@export var character_data: CharacterData   # 3.4 — stats + move set (overrides per-instance exports)
@export var move_fast: MoveData       # 2.3 — light attack frame data (jab)
@export var move_heavy: MoveData      # 2.3 — heavy attack frame data (knockdown)
@export var move_skill: MoveData      # 3.1 — skill attack frame data
@export var move_ultimate: MoveData   # 3.1 — ultimate attack frame data
@export var move_air_fast: MoveData   # air fast attack frame data (jump-in poke)
@export var move_air_heavy: MoveData  # air heavy attack frame data (spike)

# 3.4 — per-character movement (defaults = the consts above; overridden by CharacterData).
var _walk_speed: float = WALK_SPEED
var _walk_b_speed: float = WALK_B_SPEED
var _jump_velocity: float = JUMP_VELOCITY
var _jump_f_speed: float = JUMP_F_SPEED
var _gravity: float = GRAVITY
# 6.3 — per-character dash stats (defaults = the consts; overridden by CharacterData).
var _dash_speed: float = DASH_SPEED
var _dash_frames: int = DASH_TOTAL
var _backdash_speed: float = BACKDASH_SPEED
var _backdash_frames: int = BACKDASH_TOTAL

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
const JUGGLE_DECAY: float = 0.8       # 3.5: hitstun multiplier per subsequent airborne hit
const PUSHBACK_DECAY: float = 0.85    # per-frame pushback falloff (2.4 — blockstrings self-space)
var health: int = MAX_HEALTH
var _meter: UltimateMeter = UltimateMeter.new()   # charges on damage; full bar gates the ultimate
var _max_health: int = MAX_HEALTH     # 6.3: per-character; overridden from CharacterData in _apply_character_data
var _current_move: MoveData = null    # the move the active attack state is reading
var _move_has_hit: bool = false       # one hit per attack: cleared when a new attack starts
var _hitstop: int = 0                 # impact freeze; pauses everything incl. frame_in_state
var _stun_frames: int = 0             # length of the current HITSTUN/BLOCKSTUN
var _pushback_vel: float = 0.0        # px/frame applied during a reaction, decaying
var _projectile_spawned_this_move: bool = false   # 3.2: one projectile per attack
var _juggle_count: int = 0   # 3.5: airborne hits accumulated this combo; resets on landing
var _air_attack_used: bool = false   # one air attack per jump; cleared on landing / fresh jump
var _cinematic_locked: bool = false   # 7.3: UltimateCinematic owns this fighter while set

# 7.5 — training dummies are planted: they still take damage and react
# (HITSTUN/KNOCKDOWN animations play out in place), but hit/block pushback
# never slides them, so combos can be practiced without chasing the dummy
# into a corner. The training scene also makes pushbox separation shove only
# the mobile side when this is set. Never set in versus.
var pushback_immune: bool = false
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
	_apply_character_data()
	health = _max_health   # 6.3: the field initializer ran before stats loaded; seed from the real max
	_box.color = box_color
	# Validate frame data on load (conventions: validate with assert/push_error).
	for m in [move_fast, move_heavy, move_skill, move_ultimate, move_air_fast, move_air_heavy]:
		if m != null:
			m.validate()
	for m in [move_air_fast, move_air_heavy]:
		if m != null and (m.is_grab or m.is_counter):
			push_error("air move '%s': grabs/counters are ground-only" % m.move_name)
	# Tell Godot the scene-file position is the true starting point — prevents the
	# interpolator from visually sliding in from the origin on the first frame.
	reset_physics_interpolation()


## Character-select hook — call once, same frame as _ready (e.g. from the spawning
## scene's own _ready), to override whatever CharacterData/box_color the scene
## authored. Re-runs the same stat/move application _ready uses, just later.
func set_character(data: CharacterData, color: Color) -> void:
	character_data = data
	_apply_character_data()
	box_color = color
	_box.color = color


## 3.4 — pull stats + moves from CharacterData (if assigned). Called first in _ready.
func _apply_character_data() -> void:
	if character_data == null:
		return
	if character_data.move_fast != null: move_fast = character_data.move_fast
	if character_data.move_heavy != null: move_heavy = character_data.move_heavy
	if character_data.move_skill != null: move_skill = character_data.move_skill
	if character_data.move_ultimate != null: move_ultimate = character_data.move_ultimate
	if character_data.move_air_fast != null: move_air_fast = character_data.move_air_fast
	if character_data.move_air_heavy != null: move_air_heavy = character_data.move_air_heavy
	_walk_speed = character_data.walk_speed
	_walk_b_speed = character_data.walk_b_speed
	_jump_velocity = character_data.jump_velocity
	_jump_f_speed = character_data.jump_f_speed
	_gravity = character_data.gravity
	_dash_speed = character_data.dash_speed
	_dash_frames = character_data.dash_frames
	_backdash_speed = character_data.backdash_speed
	_backdash_frames = character_data.backdash_frames
	if character_data.max_health > 0:
		_max_health = character_data.max_health


func _physics_process(_delta: float) -> void:
	# Cinematic ultimate (7.3): the UltimateCinematic sequencer owns this fighter —
	# no input, no movement, no hitstop decay until released.
	if _cinematic_locked:
		return
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
					_vel.x = _jump_f_speed * facing
				elif buf.is_held(bwd_bit):
					_fsm.request(CharacterStateMachine.State.JUMP_B)
					_vel.x = -_jump_f_speed * facing
				else:
					_fsm.request(CharacterStateMachine.State.JUMP_AIR)
					_vel.x = 0.0
				_vel.y = _jump_velocity
		CharacterStateMachine.State.JUMP_LAND:
			if _fsm.frame_in_state >= JUMP_LAND_FRAMES:
				_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.DASH:
			if _fsm.frame_in_state >= _dash_frames:
				_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.BACKDASH:
			if _fsm.frame_in_state >= _backdash_frames:
				_fsm.request(CharacterStateMachine.State.IDLE)
		CharacterStateMachine.State.FAST_ATTACK, CharacterStateMachine.State.HEAVY_ATTACK, \
		CharacterStateMachine.State.SKILL:
			if _current_move == null or _fsm.frame_in_state >= _current_move.total():
				if position.y < _floor_y:
					_fsm.request(CharacterStateMachine.State.JUMP_AIR)
				else:
					_fsm.request(CharacterStateMachine.State.IDLE)
			elif _current_move.in_cancel_window(_fsm.frame_in_state):
				_try_cancel_input(buf)
		CharacterStateMachine.State.AIR_FAST_ATTACK, CharacterStateMachine.State.AIR_HEAVY_ATTACK:
			# Finished while still airborne → neutral fall. Landing mid-move is the
			# _apply_movement floor check (→ JUMP_LAND). No cancels in air (v1).
			if _current_move == null or _fsm.frame_in_state >= _current_move.total():
				_fsm.request(CharacterStateMachine.State.JUMP_AIR)
		CharacterStateMachine.State.GRAB_ATTEMPT:
			# 6.4 — whiffed grab recovers to IDLE. A CONNECT is resolved externally
			# (ThrowSequencer moves us to THROW_RELEASE before this fires). GRABBED
			# and THROW_RELEASE have no timed exit here: the sequencer owns them.
			if _current_move == null or _fsm.frame_in_state >= _current_move.total():
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

	# Airborne: air attacks (one per jump, heavy > fast) then air control.
	# During an air attack the fighter is committed — momentum keeps, no steering.
	if CharacterStateMachine.is_airborne(_fsm.state):
		if CharacterStateMachine.is_attacking(_fsm.state):
			return
		if not _air_attack_used:
			if move_air_heavy != null and buf.pressed_within(InputBuffer.HEAVY, ATTACK_BUFFER) \
					and _fsm.request(CharacterStateMachine.State.AIR_HEAVY_ATTACK):
				_arm(move_air_heavy)
				_air_attack_used = true
				return
			if move_air_fast != null and buf.pressed_within(InputBuffer.FAST, ATTACK_BUFFER) \
					and _fsm.request(CharacterStateMachine.State.AIR_FAST_ATTACK):
				_arm(move_air_fast)
				_air_attack_used = true
				return
		if fwd_held:
			_vel.x = _jump_f_speed * facing
		elif bwd_held:
			_vel.x = -_jump_f_speed * facing
		else:
			_vel.x = 0.0
		return

	if not CharacterStateMachine.is_actionable(_fsm.state):
		return

	# Attacks (2.3) — buffered presses, checked while actionable. Priority: Ultimate > Heavy > Skill > Fast.
	# On a successful start, arm the move and clear the one-hit latch.
	# NOTE: Treating ultimate as a second SKILL slot to avoid changing FSM structure (Phase 3.1 constraint).
	# 6.4: a slot whose move is_grab enters GRAB_ATTEMPT instead (grapplers put grabs on SKILL/ULT).
	if move_ultimate != null and _meter.is_full() \
			and buf.pressed_within(InputBuffer.ULTIMATE, ATTACK_BUFFER) \
			and _fsm.request(_attack_state_for(move_ultimate, CharacterStateMachine.State.SKILL)):
		_arm(move_ultimate)
		_meter.consume()   # spent the moment the move starts — blocked/whiffed is still spent
		return
	if move_heavy != null and buf.pressed_within(InputBuffer.HEAVY, ATTACK_BUFFER) \
			and _fsm.request(_attack_state_for(move_heavy, CharacterStateMachine.State.HEAVY_ATTACK)):
		_arm(move_heavy)
		return
	if move_skill != null and buf.pressed_within(InputBuffer.SKILL, ATTACK_BUFFER) \
			and _fsm.request(_attack_state_for(move_skill, CharacterStateMachine.State.SKILL)):
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
		# Latch also clears here (not just on landing): a fighter hit out of an air
		# attack can ride hitstun to the floor and exit to IDLE without ever passing
		# the landing block — without this a stuck latch would eat the next jump.
		if _fsm.request(CharacterStateMachine.State.JUMP_START):
			_air_attack_used = false
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
			_vel.x = _walk_speed * facing
			_vel.y = 0.0
		CharacterStateMachine.State.WALK_B:
			_vel.x = -_walk_b_speed * facing
			_vel.y = 0.0
		CharacterStateMachine.State.DASH:
			_vel.x = _dash_speed * facing
			_vel.y = 0.0
		CharacterStateMachine.State.BACKDASH:
			_vel.x = -_backdash_speed * facing
			_vel.y = 0.0
		CharacterStateMachine.State.JUMP_AIR, CharacterStateMachine.State.JUMP_F, \
		CharacterStateMachine.State.JUMP_B, \
		CharacterStateMachine.State.AIR_FAST_ATTACK, CharacterStateMachine.State.AIR_HEAVY_ATTACK:
			_vel.y += _gravity   # horizontal vel preserved from jump launch / attack start
		CharacterStateMachine.State.HITSTUN, CharacterStateMachine.State.BLOCKSTUN:
			# Pushback (2.4): slide away from the attacker, decaying
			_vel.x = _pushback_vel
			if position.y < _floor_y:
				_vel.y += _gravity
			else:
				_vel.y = 0.0
			_pushback_vel *= PUSHBACK_DECAY
		CharacterStateMachine.State.KNOCKDOWN, CharacterStateMachine.State.KO:
			# KO falls like KNOCKDOWN: a fighter can die with airborne velocity
			# (throw slam pop, juggle kill) and the body must arc back to the
			# floor — the default arm would freeze _vel.y and float it away.
			if position.y < _floor_y:
				_vel.y += _gravity
			else:
				_vel.y = 0.0
			_vel.x = 0.0
		CharacterStateMachine.State.GRABBED, CharacterStateMachine.State.THROW_RELEASE:
			# 6.4 — locked in a throw; the ThrowSequencer positions the victim.
			_vel = Vector2.ZERO
		CharacterStateMachine.State.FAST_ATTACK, CharacterStateMachine.State.HEAVY_ATTACK, \
		CharacterStateMachine.State.SKILL:
			# 6.3 — a move can carry its own grounded travel (dash kick / storm kick).
			# 0 when no move is armed or the frame is outside the move's velocity window.
			# Hitstop early-returns before this, so freezes cost no distance.
			_vel.x = _current_move.velocity_at(_fsm.frame_in_state) * facing if _current_move != null else 0.0
			_vel.y = 0.0
		_:
			# IDLE, CROUCH, BLOCK, JUMP_START, JUMP_LAND, GETUP — no lateral movement.
			_vel.x = 0.0

	position += _vel

	# Land when airborne and at or past the floor.
	if CharacterStateMachine.is_airborne(_fsm.state) and position.y >= _floor_y:
		position.y = _floor_y
		_vel = Vector2.ZERO
		_juggle_count = 0
		_air_attack_used = false
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


# 6.4 — the FSM state a move slot enters: grabs go to GRAB_ATTEMPT, strikes to
# their normal state.
func _attack_state_for(move: MoveData, strike_state: CharacterStateMachine.State) -> CharacterStateMachine.State:
	return CharacterStateMachine.State.GRAB_ATTEMPT if move.is_grab else strike_state


## Arm a freshly-started attack: set the move and clear per-attack latches.
func _arm(move: MoveData) -> void:
	_current_move = move
	_move_has_hit = false
	_projectile_spawned_this_move = false


# 3.5 — called only while in_cancel_window() is true. Checks buffered attack inputs and
# fires the first legal cancel in escalation order. Downgrade cancels (heavy→fast) are
# not allowed; order is fast→heavy, (fast|heavy)→skill, any_attack→ultimate.
# 6.4: grab moves are never cancel targets — command grabs must be raw.
# 6.2: counter moves likewise — the stance must be raw, or blocked-heavy→stance is a degenerate frame trap.
func _try_cancel_input(buf: InputBuffer) -> void:
	var cur := _fsm.state
	if move_ultimate != null and not move_ultimate.is_grab and not move_ultimate.is_counter \
			and _meter.is_full() \
			and buf.pressed_within(InputBuffer.ULTIMATE, ATTACK_BUFFER):
		_cancel_into(CharacterStateMachine.State.SKILL, move_ultimate)
		if _current_move == move_ultimate:   # consume iff the cancel actually armed it
			_meter.consume()
		return
	if move_skill != null and not move_skill.is_grab and not move_skill.is_counter \
			and cur != CharacterStateMachine.State.SKILL \
			and buf.pressed_within(InputBuffer.SKILL, ATTACK_BUFFER):
		_cancel_into(CharacterStateMachine.State.SKILL, move_skill)
		return
	if move_heavy != null and cur == CharacterStateMachine.State.FAST_ATTACK \
			and buf.pressed_within(InputBuffer.HEAVY, ATTACK_BUFFER):
		_cancel_into(CharacterStateMachine.State.HEAVY_ATTACK, move_heavy)


func _cancel_into(target: CharacterStateMachine.State, move: MoveData) -> void:
	_fsm.request(CharacterStateMachine.State.IDLE)
	if _fsm.request(target):
		_arm(move)


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

## Per-character max health (6.3/6.4 — e.g. Sofia 900, Jacob 1150; defaults to
## MAX_HEALTH). HUD callers divide the current health by this for the bar fraction.
func get_max_health() -> int:
	return _max_health

## Ultimate meter (spec 2026-07-04). Deal-side gain is credited by the SCENES —
## the call sites that already orchestrate both fighters (main.gd _try_hit,
## projectile passes, ThrowSequencer). Take-side gain is internal to apply_*.
func on_damage_dealt(amount: int) -> void:
	_meter.gain_dealt(amount)

func get_meter_fraction() -> float:
	return _meter.fraction()

func is_ultimate_ready() -> bool:
	return _meter.is_full()

## Training mode: pin the bar full each frame.
func fill_meter() -> void:
	_meter.fill()

## Frames elapsed in the current FSM state (0 on the entry frame). Used by training HUD
## to compute exact frame advantage at the moment of contact.
func get_frame_in_state() -> int:
	return _fsm.frame_in_state

## Frozen during hitstop or a cinematic ultimate — main.gd skips resolution and
## the MatchManager pauses the round timer while either fighter is frozen.
func is_frozen() -> bool:
	return _hitstop > 0 or _cinematic_locked

## Invulnerable on wake-up (GETUP), when KO'd, while held in a throw (GRABBED, 6.4),
## or during a move's startup-invuln window (3.4).
func is_invulnerable() -> bool:
	if _fsm.state == CharacterStateMachine.State.GETUP or _fsm.state == CharacterStateMachine.State.KO \
			or _fsm.state == CharacterStateMachine.State.GRABBED:
		return true
	if _current_move != null and CharacterStateMachine.is_attacking(_fsm.state) \
			and _current_move.is_invuln_at(_fsm.frame_in_state):
		return true
	return false

## 6.2 — true while the current move is a counter stance in its live window.
## Consulted by the scenes at classification time (mirrors is_invulnerable()).
func is_countering() -> bool:
	return _current_move != null and _current_move.is_counter \
		and CharacterStateMachine.is_attacking(_fsm.state) \
		and _current_move.is_active(_fsm.frame_in_state)

## True while holding the away-from-opponent direction (the block input, 2.4).
func is_holding_back() -> bool:
	var buf: InputBuffer = InputManager.get_buffer(player_index)
	var bwd_bit: int = InputBuffer.LEFT if facing > 0 else InputBuffer.RIGHT
	return buf.is_held(bwd_bit)

## The move currently being executed — non-null throughout startup/active/recovery.
## Unlike get_active_move(), does NOT filter by hit state; used for training readouts.
func get_current_move() -> MoveData:
	if _current_move == null or not CharacterStateMachine.is_attacking(_fsm.state):
		return null
	return _current_move

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
## 3.5: hitstun is scaled by JUGGLE_DECAY^juggle_count when the defender is airborne.
func apply_hit(move: MoveData, push_dir: float) -> void:
	health = maxi(0, health - move.damage)
	_meter.gain_taken(move.damage)
	_pushback_vel = 0.0 if pushback_immune else move.pushback_hit * push_dir
	if position.y < _floor_y:
		_stun_frames = maxi(1, int(move.hitstun * pow(JUGGLE_DECAY, _juggle_count)))
		_juggle_count += 1
	else:
		_stun_frames = move.hitstun
	if move.causes_knockdown:
		_fsm.on_launched()   # → KNOCKDOWN
	else:
		_fsm.on_hit()        # → HITSTUN

## Resolve a blocked hit (2.4) — no damage (no chip in v1), BLOCKSTUN, more pushback.
func apply_block(move: MoveData, push_dir: float) -> void:
	_stun_frames = move.blockstun
	_pushback_vel = 0.0 if pushback_immune else move.pushback_block * push_dir
	_fsm.on_blocked()        # → BLOCKSTUN

## 6.2 — successful counter: release the stance to neutral immediately (the same
## busy-exit request used at total()). The retaliation itself was applied to the
## ATTACKER by the scene via apply_hit; nothing to apply on the defender side.
func end_counter() -> void:
	if CharacterStateMachine.is_attacking(_fsm.state):
		_fsm.request(CharacterStateMachine.State.IDLE)

## Resolve a projectile clean hit (3.2) — same effect as apply_hit, ProjectileData payload.
func apply_hit_proj(data: ProjectileData, push_dir: float) -> void:
	health = maxi(0, health - data.damage)
	_meter.gain_taken(data.damage)
	_stun_frames = data.hitstun
	_pushback_vel = 0.0 if pushback_immune else data.pushback_hit * push_dir
	if data.causes_knockdown:
		_fsm.on_launched()
	else:
		_fsm.on_hit()

## Resolve a blocked projectile (3.2) — no damage, blockstun, more pushback.
func apply_block_proj(data: ProjectileData, push_dir: float) -> void:
	_stun_frames = data.blockstun
	_pushback_vel = 0.0 if pushback_immune else data.pushback_block * push_dir
	_fsm.on_blocked()

# --- Grab/throw API (6.4) — driven by ThrowSequencer (match/training scenes) ---

## World-space grab box while a grab move is in its active connect window (empty
## otherwise). Separate from get_hitboxes() so strike resolution never sees it.
func get_grab_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _fsm.state != CharacterStateMachine.State.GRAB_ATTEMPT:
		return out
	if _move_has_hit or _current_move == null or not _current_move.is_grab:
		return out
	for h in _current_move.hitboxes_at(_fsm.frame_in_state):
		out.append(CombatBoxes.to_world(h, position, facing))
	return out

## The grab move being attempted or thrown with (null outside grab states).
func get_grab_move() -> MoveData:
	if _current_move == null or not _current_move.is_grab:
		return null
	if _fsm.state != CharacterStateMachine.State.GRAB_ATTEMPT \
			and _fsm.state != CharacterStateMachine.State.THROW_RELEASE:
		return null
	return _current_move

## Attacker side of a connect: latch the one-connect flag and start the throw.
func begin_throw() -> void:
	mark_move_hit()
	_fsm.request(CharacterStateMachine.State.THROW_RELEASE)

## Attacker released (throw finished or teched) — back to neutral.
func end_throw() -> void:
	if _fsm.state == CharacterStateMachine.State.THROW_RELEASE:
		_fsm.request(CharacterStateMachine.State.IDLE)

## Victim side of a connect: forced into GRABBED, fully passive (no input — not
## actionable; no movement — sequencer snaps position; strike-invulnerable).
func apply_grabbed() -> void:
	_current_move = null
	active_hitboxes_local = []
	_vel = Vector2.ZERO
	_pushback_vel = 0.0
	_fsm.force(CharacterStateMachine.State.GRABBED)

## Victim freed without damage (tech, or the thrower got interrupted).
func release_from_grab() -> void:
	if _fsm.state == CharacterStateMachine.State.GRABBED:
		_fsm.request(CharacterStateMachine.State.IDLE)

## The slam: damage + vertical pop into KNOCKDOWN. Lifted 1px off the floor so
## the knockdown arc integrates gravity instead of zeroing the pop immediately.
func apply_throw(move: MoveData) -> void:
	health = maxi(0, health - move.damage)
	_meter.gain_taken(move.damage)
	position.y = minf(position.y, _floor_y - 1.0)
	_vel = Vector2(0.0, move.throw_launch_y)
	_pushback_vel = 0.0
	_fsm.on_launched()   # → KNOCKDOWN


# --- Cinematic ultimate API (7.3) — driven by UltimateCinematic (match scene) ---

## Lock this fighter for the cutscene: fully passive (no input, no physics — the
## sequencer positions both fighters directly) and is_frozen() → the scene pauses
## hit/throw/projectile resolution and the round timer, exactly like hitstop.
func begin_cinematic_lock() -> void:
	_cinematic_locked = true
	_vel = Vector2.ZERO
	_pushback_vel = 0.0

## Attacker released at the end of the sequence: drop the armed ultimate (its
## normal hitboxes must never go live) and return to neutral.
func end_cinematic_attacker() -> void:
	_cinematic_locked = false
	_current_move = null
	active_hitboxes_local = []
	_fsm.request(CharacterStateMachine.State.IDLE)

## 7.5 — release for a cinematic BYSTANDER (training: the other arena's pair is
## locked while a cutscene plays in this one). Unlike the attacker/finisher
## releases, nothing else changes: the fighter resumes exactly where it froze.
func end_cinematic_lock() -> void:
	_cinematic_locked = false

## Scripted damage from one cinematic strike — no stun, no state change (the
## victim stays locked; their reaction is the sequencer's choreography).
func apply_cinematic_damage(amount: int) -> void:
	health = maxi(0, health - amount)

## The finisher: remaining damage + release + vertical pop into KNOCKDOWN
## (throw-style: lifted 1px so the knockdown arc integrates gravity).
func apply_cinematic_finisher(amount: int, launch_y: float) -> void:
	_cinematic_locked = false
	health = maxi(0, health - amount)
	position.y = minf(position.y, _floor_y - 1.0)
	_vel = Vector2(0.0, launch_y)
	_pushback_vel = 0.0
	_current_move = null
	active_hitboxes_local = []
	_fsm.on_launched()   # → KNOCKDOWN


## Force the KO state on the round loser (2.6).
func force_ko() -> void:
	_fsm.on_ko()

## Reset everything for a fresh round (2.6).
func reset_for_round(spawn_x: float) -> void:
	position = Vector2(spawn_x, _floor_y)
	health = _max_health
	_vel = Vector2.ZERO
	_hitstop = 0
	_stun_frames = 0
	_pushback_vel = 0.0
	_current_move = null
	_move_has_hit = false
	_projectile_spawned_this_move = false
	_juggle_count = 0
	_air_attack_used = false
	_cinematic_locked = false
	# _meter deliberately NOT reset — meter carries across rounds (spec 2026-07-04);
	# a fresh match starts at 0 because controllers are freshly instantiated.
	active_hitboxes_local = []
	_fsm.reset(CharacterStateMachine.State.IDLE)
	reset_physics_interpolation()
