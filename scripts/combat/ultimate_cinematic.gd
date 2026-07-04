class_name UltimateCinematic
extends RefCounted
## 7.3 — Cinematic ultimates. Scene-owned, like ThrowSequencer: the match scene
## calls try_start() each frame and then step() once per physics frame until it
## returns true. Two choreographies, picked by MoveData.cinematic_style
## (authored in .local/gamePlan.md → per-character movesets):
##
## "rush" (Jerb: "Iron Barrage — The Four Corners"): the attacker traps the
## opponent up close and lands four devastating punches — each with a
## stretched slow-motion windup and an impact flash + camera shake — ending
## with the launching knockout blow.
##
## "sky_rally" (Rainne: "Sky Rally", cinematic aerial finisher): she keeps the
## takraw ball airborne through controlled kicks — Rising Kick, Aerial Control
## (she follows it up), Spinning Kick (a full mid-air rotation) — then a
## bicycle-kick Final Spike sends the ball crashing down into the opponent.
## Only the spike touches the victim; the rally is her showcase.
##
## "slam" (Jacob: "Earthbreaker", cinematic super grab): a heavy stomping lunge
## to the opponent, the clinch, then he hoists them inverted overhead, hangs a
## slow-mo beat at the apex, and piledrives them into the ground with a
## shockwave. The victim barely moves — the world stops instead (grappler
## weight, deliberately no Sett-style carry: no free corner position on top of
## the round-ending damage).
##
## Shared frame: on the first frame of a move flagged is_cinematic, both
## fighters are locked (is_frozen() → hits, throws, projectiles and the round
## timer all pause), the HUD is hidden, letterbox bars slide in and the camera
## zooms on the attacker. At the end the victim is launched into KNOCKDOWN and
## the camera pulls back out as the HUD returns. The victim cannot act at any
## point.
##
## Slow motion is choreographic: everything else in the match is frozen, so
## stretching the windup frame counts reads as slowmo without touching
## Engine.time_scale (no global state to restore, no pause-menu interactions).

const CSM := preload("res://scripts/fsm/character_state_machine.gd")

# --- Shared choreography (frames @60Hz) ---
const ZOOM_IN_FRAMES: int = 36
const LAUNCH_FRAMES: int = 18        # victim flies back before the knockdown pop
const ZOOM_OUT_FRAMES: int = 32
const LAUNCH_SPEED: float = 14.0     # victim flyback px/frame at launch start
const LAUNCH_POP_Y: float = -7.0     # finisher vertical pop (falls into KNOCKDOWN)

const FOCUS_ZOOM: float = 2.0
const FINAL_ZOOM: float = 2.4        # extra push-in on the finisher windup
const FOCUS_Y: float = 470.0         # camera y while zoomed (fighters at floor 560)
const HOME_POS := Vector2(640, 360)  # identity view for the 1280x720 canvas
const BAR_H: float = 70.0            # letterbox bar height

# --- "rush" choreography ---
const RUN_SPEED: float = 12.0        # px/frame toward the victim
const RUN_CAP: int = 120             # safety: never run longer than this
const STRIKE_GAP: float = 64.0       # attacker holds this distance while striking
const WINDUP_FRAMES: int = 24        # hits 1-3: slow pull-back
const THRUST_FRAMES: int = 4         # ...then a fast lunge
const HOLD_FRAMES: int = 12          # impact freeze, hits 1-3
const RECOVER_FRAMES: int = 10
const FINAL_WINDUP: int = 42         # hit 4: longer, deeper zoom
const FINAL_THRUST: int = 5
const FINAL_HOLD: int = 24
const PULLBACK: float = 10.0         # attacker lean-back depth during windup
const LUNGE: float = 36.0            # attacker thrust depth past his anchor
const IMPACT_NUDGE: float = 8.0      # victim shoved back per non-final hit

# --- "sky_rally" choreography ---
const KICK_WINDUPS: Array[int] = [18, 20, 22, 26]   # slow-mo beat before each kick
const RALLY_STRIKE_FRAMES: int = 12                 # ball pop up to its next apex
# Rainne's lift per kick: grounded hop, then she follows the ball up.
const KICK_HEIGHTS: Array[float] = [-14.0, -150.0, -210.0, -264.0]
const BALL_APEX: Array[float] = [-230.0, -300.0, -330.0]  # ball height after kicks 1-3
const BALL_START_Y: float = -50.0    # the ball starts at her feet/knee height
const BALL_SAG: float = 34.0         # gravity pull on the ball during each windup
const JUGGLE_X: float = 26.0         # ball held this far in front of Rainne
const BALL_SIZE: float = 26.0        # a takraw ball, not a boulder
const SPIKE_SPEED: float = 30.0      # px/frame of the final spike
const SPIKE_CAP: int = 120           # safety: force the impact if it overruns
const BLAST_FRAMES: int = 18         # explosion hold before the launch
const BLAST_SIZE: float = 96.0
const CHEST_Y: float = -56.0         # impact height above the feet origin
const RALLY_ZOOM: float = 1.7        # wide enough to frame her and the ball
const BALL_COLOR := Color(0.95, 0.8, 0.35, 0.95)   # rattan-ball glow
const BLAST_COLOR := Color(1.0, 0.85, 0.45, 0.95)

# --- "slam" choreography ---
const LUNGE_SPEED: float = 9.0       # heavy, deliberate — slower than Jerb's run
const LUNGE_CAP: int = 130           # safety: never lunge longer than this
const CLINCH_GAP: float = 48.0       # matches ThrowSequencer's hold offset
const CLINCH_FRAMES: int = 18
const LIFT_FRAMES: int = 30          # slow hoist — the slow-mo beat going up
const APEX_FRAMES: int = 16          # hang time, victim inverted overhead
const SLAM_FRAMES: int = 5           # the drive down is instant by contrast
const IMPACT_FRAMES: int = 22        # shockwave hold before the knockdown
const LIFT_HEIGHT: float = 150.0     # victim held this far overhead
const SLAM_BOUNCE: float = 3.0       # they barely slide — piledriven in place
const SHOCKWAVE_W: float = 340.0     # ground shockwave full width
const SHOCKWAVE_COLOR := Color(0.85, 0.75, 0.55, 0.9)   # dust off the floor

# Damage split across the pre-finisher hits (fractions of move.damage); the
# finisher takes the remainder so the total always equals the authored damage.
# Sky Rally and Earthbreaker are single blows: everything on the finisher.
const RUSH_FRACTIONS: Array[float] = [0.15, 0.2, 0.25]
const FINISHER_ONLY: Array[float] = []

enum Phase { ZOOM_IN, RUN, WINDUP, THRUST, HOLD, RECOVER, LAUNCH, ZOOM_OUT,
	RALLY_WINDUP, RALLY_STRIKE, SPIKE_FLIGHT, BLAST,
	LUNGE, CLINCH, LIFT, APEX, SLAM, IMPACT }

var attacker: CharacterController
var victim: CharacterController

var _camera: Camera2D
var _hud: CanvasLayer
var _fx: CanvasLayer = null
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _flash: ColorRect

var _left_x: float = 50.0
var _right_x: float = 1230.0
var _floor_y: float = 560.0

var _style: String = "rush"
var _phase: int = Phase.ZOOM_IN
var _t: int = 0                     # frames in the current phase
var _hit: int = 0                   # rush: strike index / sky_rally: kick index
var _hit_damages: Array[int] = []
var _atk_base_x: float = 0.0        # attacker ground anchor
var _atk_from_y: float = 0.0        # height eased from at each rally windup
var _victim_start_y: float = 0.0    # eased to the floor during ZOOM_IN
var _shake: float = 0.0
var _zoom_out_from_pos: Vector2 = Vector2.ZERO
var _zoom_out_from_zoom: float = 1.0
var _launch_vel: float = 0.0
var _done: bool = false

# world-space fx + fighter-box spins (sky_rally + slam)
var _world_fx: Node2D = null
var _ball: ColorRect = null         # sky_rally: takraw ball/blast; slam: shockwave
var _ball_pos: Vector2 = Vector2.ZERO
var _ball_from: Vector2 = Vector2.ZERO   # where the last touch left it (sag base)
var _atk_box: ColorRect = null      # the attacker's visual Box, spun for kicks 3/4
var _vic_box: ColorRect = null      # the victim's visual Box, inverted during the lift


## Detect + begin a cinematic ultimate this frame. Returns a live sequencer, or
## null. Fires only on the move's entry frame (frame_in_state == 0), so a denied
## start (e.g. the scene skipped us during a live throw) degrades gracefully:
## the move simply resolves as the normal strike it also authors.
static func try_start(atk: CharacterController, def: CharacterController,
		camera: Camera2D, hud: CanvasLayer, fx_parent: Node,
		left_x: float, right_x: float) -> UltimateCinematic:
	var move: MoveData = atk.get_current_move()
	if move == null:
		move = atk.get_grab_move()   # a grab ultimate (Jacob) sits in GRAB_ATTEMPT, not SKILL
	if move == null or not move.is_cinematic:
		return null
	var st: int = atk.fsm_state()
	if (st != CSM.State.SKILL and st != CSM.State.GRAB_ATTEMPT) \
			or atk.get_frame_in_state() != 0:
		return null
	# No cutscene on a KO'd body or a fighter inside a throw pair.
	if def.fsm_state() == CSM.State.KO or def.fsm_state() == CSM.State.GRABBED \
			or def.fsm_state() == CSM.State.THROW_RELEASE:
		return null

	var seq := UltimateCinematic.new()
	seq.attacker = atk
	seq.victim = def
	seq._camera = camera
	seq._hud = hud
	seq._left_x = left_x
	seq._right_x = right_x
	seq._style = move.cinematic_style
	seq._begin(move, fx_parent)
	return seq


## Advance one physics frame. Called unconditionally by the scene (the lock
## itself is what reports frozen, so this must not be gated on is_frozen()).
## Returns true when the sequence is finished and the camera is home.
func step() -> bool:
	if _done:
		return true
	_t += 1
	var dir: float = float(attacker.facing)
	match _phase:
		Phase.ZOOM_IN:
			_step_zoom_in()
		Phase.RUN:
			_step_run(dir)
		Phase.WINDUP:
			_step_windup(dir)
		Phase.THRUST:
			_step_thrust(dir)
		Phase.HOLD:
			_step_hold()
		Phase.RECOVER:
			_step_recover(dir)
		Phase.RALLY_WINDUP:
			_step_rally_windup(dir)
		Phase.RALLY_STRIKE:
			_step_rally_strike(dir)
		Phase.SPIKE_FLIGHT:
			_step_spike_flight(dir)
		Phase.BLAST:
			_step_blast()
		Phase.LUNGE:
			_step_lunge(dir)
		Phase.CLINCH:
			_step_clinch(dir)
		Phase.LIFT:
			_step_lift(dir)
		Phase.APEX:
			_step_apex(dir)
		Phase.SLAM:
			_step_slam(dir)
		Phase.IMPACT:
			_step_impact()
		Phase.LAUNCH:
			_step_launch(dir)
		Phase.ZOOM_OUT:
			_step_zoom_out()
	_decay_fx()
	return _done


func is_done() -> bool:
	return _done


# --- Shared phases ---

func _step_zoom_in() -> void:
	var e: float = _ease(_t / float(ZOOM_IN_FRAMES))
	var focus: Vector2 = _cam_clamp(Vector2(attacker.position.x, FOCUS_Y), FOCUS_ZOOM)
	_camera.position = HOME_POS.lerp(focus, e)
	_camera.zoom = Vector2.ONE * lerpf(1.0, FOCUS_ZOOM, e)
	_set_bars(BAR_H * e)
	# Ground a frozen airborne victim so the finisher lines up at body height.
	victim.position.y = lerpf(_victim_start_y, _floor_y, e)
	if _t >= ZOOM_IN_FRAMES:
		match _style:
			"sky_rally":
				_atk_base_x = attacker.position.x
				_atk_from_y = _floor_y
				_ball_pos = Vector2(_juggle_x(), _floor_y + BALL_START_Y)
				_ball_from = _ball_pos
				_enter(Phase.RALLY_WINDUP)
			"slam":
				_enter(Phase.LUNGE)
			_:
				_enter(Phase.RUN)


func _step_launch(dir: float) -> void:
	victim.position.x = _clamp_stage_x(victim.position.x + _launch_vel * dir)
	_launch_vel = maxf(2.0, _launch_vel * 0.88)
	var zoom: float = lerpf(FINAL_ZOOM, FOCUS_ZOOM, _t / float(LAUNCH_FRAMES))
	_follow(Vector2(victim.position.x, FOCUS_Y), 0.25, zoom)
	if _t >= LAUNCH_FRAMES:
		victim.apply_cinematic_finisher(_hit_damages.back(), LAUNCH_POP_Y)
		attacker.end_cinematic_attacker()
		_zoom_out_from_pos = _camera.position
		_zoom_out_from_zoom = _camera.zoom.x
		_enter(Phase.ZOOM_OUT)


func _step_zoom_out() -> void:
	# Fighters are already released — the victim falls into knockdown while the
	# camera pulls home and the bars slide away.
	var e: float = _ease(_t / float(ZOOM_OUT_FRAMES))
	_camera.position = _zoom_out_from_pos.lerp(HOME_POS, e)
	_camera.zoom = Vector2.ONE * lerpf(_zoom_out_from_zoom, 1.0, e)
	_set_bars(BAR_H * (1.0 - e))
	if _t >= ZOOM_OUT_FRAMES:
		_finish()


# --- "rush" phases ---

func _step_run(dir: float) -> void:
	var gap: float = absf(victim.position.x - attacker.position.x)
	if gap > STRIKE_GAP and _t <= RUN_CAP:
		attacker.position.x += minf(RUN_SPEED, gap - STRIKE_GAP) * dir
		_follow(Vector2(attacker.position.x, FOCUS_Y), 0.3, FOCUS_ZOOM)
	else:
		_atk_base_x = _clamp_stage_x(victim.position.x - STRIKE_GAP * dir)
		attacker.position.x = _atk_base_x
		_enter(Phase.WINDUP)


func _step_windup(dir: float) -> void:
	var frames: int = FINAL_WINDUP if _hit == 3 else WINDUP_FRAMES
	var e: float = _ease(_t / float(frames))
	attacker.position.x = _atk_base_x - PULLBACK * e * dir
	var zoom: float = lerpf(FOCUS_ZOOM, FINAL_ZOOM, e) if _hit == 3 else FOCUS_ZOOM
	_follow(Vector2(_mid_x(), FOCUS_Y), 0.2, zoom)
	if _t >= frames:
		_enter(Phase.THRUST)


func _step_thrust(dir: float) -> void:
	var frames: int = FINAL_THRUST if _hit == 3 else THRUST_FRAMES
	var t: float = _t / float(frames)
	attacker.position.x = _atk_base_x + (-PULLBACK + (PULLBACK + LUNGE) * t) * dir
	_follow(Vector2(_mid_x(), FOCUS_Y), 0.25, FINAL_ZOOM if _hit == 3 else FOCUS_ZOOM)
	if _t >= frames:
		_impact(dir)
		_enter(Phase.HOLD)


func _step_hold() -> void:
	# Attacker stays extended; the flash/shake decay sells the freeze.
	if _t >= (FINAL_HOLD if _hit == 3 else HOLD_FRAMES):
		if _hit == 3:
			_launch_vel = LAUNCH_SPEED
			_enter(Phase.LAUNCH)
		else:
			_enter(Phase.RECOVER)


func _step_recover(dir: float) -> void:
	var e: float = _ease(_t / float(RECOVER_FRAMES))
	attacker.position.x = _atk_base_x + LUNGE * (1.0 - e) * dir
	if _t >= RECOVER_FRAMES:
		_hit += 1
		# Re-anchor: the victim was nudged back, keep the strike gap consistent.
		_atk_base_x = _clamp_stage_x(victim.position.x - STRIKE_GAP * dir)
		_enter(Phase.WINDUP)


func _impact(dir: float) -> void:
	if _hit < 3:
		victim.apply_cinematic_damage(_hit_damages[_hit])
		victim.position.x = _clamp_stage_x(victim.position.x + IMPACT_NUDGE * dir)
		_flash.color.a = 0.45
		_shake = 5.0
	else:
		# Finisher damage/state land at the end of LAUNCH; here it's pure drama.
		_flash.color.a = 0.9
		_shake = 12.0


# --- "sky_rally" phases ---

func _step_rally_windup(dir: float) -> void:
	# The slow-mo beat: she moves into position for the next touch while the
	# ball hangs, sagging under gravity. Kick 3 adds the full spin; kick 4 the
	# reverse bicycle rotation.
	var frames: int = KICK_WINDUPS[_hit]
	var e: float = _ease(_t / float(frames))
	attacker.position.x = _atk_base_x - 8.0 * e * dir
	attacker.position.y = lerpf(_atk_from_y, _floor_y + KICK_HEIGHTS[_hit], e)
	if _hit == 2:
		_set_box_spin(TAU * e)        # Spinning Kick: mid-air rotation
	elif _hit == 3:
		_set_box_spin(-TAU * e)       # Final Spike: bicycle-kick flip
	_ball_pos.y = _ball_from.y + BALL_SAG * e
	_ball_set(_ball_pos, BALL_SIZE)
	var zoom: float = lerpf(RALLY_ZOOM, FINAL_ZOOM, e) if _hit == 3 else RALLY_ZOOM
	_follow(_rally_focus(), 0.2, zoom)
	if _t >= frames:
		if _hit == 3:
			# Contact: the spike sends the ball hurtling at the opponent.
			_flash.color.a = 0.5
			_shake = 7.0
			_enter(Phase.SPIKE_FLIGHT)
		else:
			_flash.color.a = 0.3
			_shake = 3.5
			_ball_from = _ball_pos
			_enter(Phase.RALLY_STRIKE)


func _step_rally_strike(dir: float) -> void:
	# The touch itself: a quick snap and the ball pops to its next apex.
	var e: float = _ease(_t / float(RALLY_STRIKE_FRAMES))
	attacker.position.x = _atk_base_x + 12.0 * (1.0 - e) * dir
	_ball_pos = Vector2(_juggle_x(), lerpf(_ball_from.y, _floor_y + BALL_APEX[_hit], e))
	_ball_set(_ball_pos, BALL_SIZE)
	_follow(_rally_focus(), 0.25, RALLY_ZOOM)
	if _t >= RALLY_STRIKE_FRAMES:
		_hit += 1
		_atk_from_y = attacker.position.y
		_ball_from = _ball_pos
		_enter(Phase.RALLY_WINDUP)


func _step_spike_flight(_dir: float) -> void:
	var target := Vector2(victim.position.x, _floor_y + CHEST_Y)
	var to: Vector2 = target - _ball_pos
	if to.length() <= SPIKE_SPEED or _t >= SPIKE_CAP:
		_ball_pos = target
		# Exact restore before the blast: she lands out of the bicycle kick.
		attacker.position = Vector2(_atk_base_x, _floor_y)
		_set_box_spin(0.0)
		_flash.color.a = 0.9
		_shake = 12.0
		_enter(Phase.BLAST)
	else:
		_ball_pos += to.normalized() * SPIKE_SPEED
		# She tumbles back toward the floor while the ball dives.
		attacker.position.x = lerpf(attacker.position.x, _atk_base_x, 0.15)
		attacker.position.y = lerpf(attacker.position.y, _floor_y, 0.15)
	_ball_set(_ball_pos, BALL_SIZE)
	_follow(_ball_pos, 0.35, 1.8)


func _step_blast() -> void:
	# The ball detonates on the victim: it swells into a blast and fades while
	# the camera holds on the hit before the launch.
	var e: float = _ease(minf(_t / 8.0, 1.0))
	var s: float = lerpf(BALL_SIZE, BLAST_SIZE, e)
	_ball.color = BALL_COLOR.lerp(BLAST_COLOR, e)
	_ball_set(Vector2(victim.position.x, _floor_y + CHEST_Y), s)
	var fade_left: int = BLAST_FRAMES - _t
	if fade_left < 8:
		_ball.color.a = BLAST_COLOR.a * (fade_left / 8.0)
	_follow(Vector2(victim.position.x, FOCUS_Y), 0.35, FINAL_ZOOM)
	if _t >= BLAST_FRAMES:
		_ball.visible = false
		_launch_vel = LAUNCH_SPEED
		_enter(Phase.LAUNCH)


# --- "slam" phases ---

func _step_lunge(dir: float) -> void:
	# Heavy stomping march — the invulnerable walk-through (everything else is
	# frozen, so the invuln is implicit; the stomp shakes sell the weight).
	var gap: float = absf(victim.position.x - attacker.position.x)
	if gap > CLINCH_GAP and _t <= LUNGE_CAP:
		attacker.position.x += minf(LUNGE_SPEED, gap - CLINCH_GAP) * dir
		if _t % 12 == 0:
			_shake = maxf(_shake, 2.5)
		_follow(Vector2(attacker.position.x, FOCUS_Y), 0.3, FOCUS_ZOOM)
	else:
		_atk_base_x = _clamp_stage_x(victim.position.x - CLINCH_GAP * dir)
		attacker.position.x = _atk_base_x
		_flash.color.a = 0.3
		_shake = 4.0
		_enter(Phase.CLINCH)


func _step_clinch(_dir: float) -> void:
	# The seize: a held beat with the camera pushing in — no escape from here.
	var e: float = _ease(_t / float(CLINCH_FRAMES))
	_follow(Vector2(_mid_x(), FOCUS_Y), 0.25, lerpf(FOCUS_ZOOM, 2.2, e))
	if _t >= CLINCH_FRAMES:
		_enter(Phase.LIFT)


func _step_lift(dir: float) -> void:
	# The hoist: the victim is carried up and turned upside down overhead —
	# the slow-mo beat going up.
	var e: float = _ease(_t / float(LIFT_FRAMES))
	victim.position.x = lerpf(attacker.position.x + CLINCH_GAP * dir,
			attacker.position.x, e)
	victim.position.y = _floor_y - LIFT_HEIGHT * e
	_set_vic_spin(PI * e)
	_follow(Vector2(attacker.position.x, FOCUS_Y - 30.0 * e), 0.2, 2.2)
	if _t >= LIFT_FRAMES:
		_enter(Phase.APEX)


func _step_apex(_dir: float) -> void:
	# Hang time: inverted at the top, a small tremble, camera at full push.
	victim.position.y = _floor_y - LIFT_HEIGHT + sin(_t * 0.7) * 2.0
	_shake = maxf(_shake, 1.2)
	_follow(Vector2(attacker.position.x, FOCUS_Y - 30.0), 0.25, FINAL_ZOOM)
	if _t >= APEX_FRAMES:
		_enter(Phase.SLAM)


func _step_slam(dir: float) -> void:
	# The piledriver: instant by contrast with the lift.
	var t: float = _t / float(SLAM_FRAMES)
	victim.position.x = attacker.position.x + 34.0 * t * dir
	victim.position.y = _floor_y - LIFT_HEIGHT * (1.0 - t * t)   # accelerating down
	if _t >= SLAM_FRAMES:
		victim.position = Vector2(
				_clamp_stage_x(attacker.position.x + 34.0 * dir), _floor_y)
		_set_vic_spin(0.0)
		_ball_pos = victim.position
		_flash.color.a = 0.9
		_shake = 14.0
		_enter(Phase.IMPACT)


func _step_impact() -> void:
	# The earth breaks: a dust shockwave races out along the floor and fades
	# while the camera holds on the crater.
	var e: float = _ease(_t / float(IMPACT_FRAMES))
	var w: float = lerpf(30.0, SHOCKWAVE_W, e)
	_ball.color = Color(SHOCKWAVE_COLOR, SHOCKWAVE_COLOR.a * (1.0 - e))
	_ball.visible = true
	_ball.position = Vector2(_ball_pos.x - w * 0.5, _floor_y - 8.0)
	_ball.size = Vector2(w, 10.0)
	_follow(Vector2(victim.position.x, FOCUS_Y), 0.3, FINAL_ZOOM)
	if _t >= IMPACT_FRAMES:
		_ball.visible = false
		_launch_vel = SLAM_BOUNCE   # piledriven in place: a bounce, not a flyback
		_enter(Phase.LAUNCH)


# --- Internals ---

func _begin(move: MoveData, fx_parent: Node) -> void:
	_floor_y = attacker.position.y   # attacker is grounded (attacks start grounded)
	_victim_start_y = victim.position.y
	attacker.begin_cinematic_lock()
	victim.begin_cinematic_lock()
	_hud.visible = false
	_split_damage(move.damage,
			RUSH_FRACTIONS if _style == "rush" else FINISHER_ONLY)
	_build_fx(fx_parent)
	if _style == "sky_rally":
		_build_world_fx(fx_parent)
		_atk_box = attacker.get_node_or_null("Box")
		if _atk_box != null:
			_atk_box.pivot_offset = _atk_box.size * 0.5   # spin about the body centre
	elif _style == "slam":
		_build_world_fx(fx_parent)   # the ball prop doubles as the shockwave
		_vic_box = victim.get_node_or_null("Box")
		if _vic_box != null:
			_vic_box.pivot_offset = _vic_box.size * 0.5   # inverted about the body centre


func _split_damage(total: int, fractions: Array[float]) -> void:
	_hit_damages.clear()
	var spent: int = 0
	for f in fractions:
		var d: int = int(total * f)
		_hit_damages.append(d)
		spent += d
	_hit_damages.append(maxi(0, total - spent))   # finisher takes the remainder


func _enter(phase: int) -> void:
	_phase = phase
	_t = 0


func _finish() -> void:
	_camera.position = HOME_POS
	_camera.zoom = Vector2.ONE
	_camera.offset = Vector2.ZERO
	_hud.visible = true
	_set_box_spin(0.0)   # safety: never leave a fighter tilted
	_set_vic_spin(0.0)
	if _fx != null:
		_fx.queue_free()
		_fx = null
	if _world_fx != null:
		_world_fx.queue_free()
		_world_fx = null
	_done = true


func _mid_x() -> float:
	return (attacker.position.x + victim.position.x) * 0.5


## World x the ball is juggled at: just in front of Rainne.
func _juggle_x() -> float:
	return _atk_base_x + JUGGLE_X * attacker.facing


## Camera target framing Rainne and the ball together during the rally.
func _rally_focus() -> Vector2:
	return Vector2(attacker.position.x, (attacker.position.y - 40.0 + _ball_pos.y) * 0.5)


## Size/position the (square) ball, centred on a world point.
func _ball_set(centre: Vector2, s: float) -> void:
	_ball.visible = true
	_ball.position = centre - Vector2(s, s) * 0.5
	_ball.size = Vector2(s, s)


func _set_box_spin(angle: float) -> void:
	if _atk_box != null:
		_atk_box.rotation = angle


func _set_vic_spin(angle: float) -> void:
	if _vic_box != null:
		_vic_box.rotation = angle


func _clamp_stage_x(x: float) -> float:
	var half_w: float = CharacterController.PUSH_W * 0.5
	return clampf(x, _left_x + half_w, _right_x - half_w)


## Camera target clamped so the zoomed view never leaves the 1280x720 canvas.
func _cam_clamp(pos: Vector2, zoom: float) -> Vector2:
	var half_w: float = 640.0 / zoom
	var half_h: float = 360.0 / zoom
	return Vector2(clampf(pos.x, half_w, 1280.0 - half_w),
			clampf(pos.y, half_h, 720.0 - half_h))


func _follow(target: Vector2, weight: float, zoom: float) -> void:
	_camera.position = _camera.position.lerp(_cam_clamp(target, zoom), weight)
	_camera.zoom = _camera.zoom.lerp(Vector2.ONE * zoom, 0.15)


func _ease(t: float) -> float:   # smoothstep
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _set_bars(h: float) -> void:
	_top_bar.offset_bottom = h
	_bottom_bar.offset_top = -h


func _decay_fx() -> void:
	_flash.color.a = 0.0 if _flash.color.a < 0.01 else _flash.color.a * 0.85
	_shake *= 0.85
	_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake \
			if _shake > 0.3 else Vector2.ZERO


func _build_fx(fx_parent: Node) -> void:
	_fx = CanvasLayer.new()
	_fx.layer = 10   # above the world; the real HUD (layer 1) is hidden anyway

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.add_child(_flash)

	_top_bar = ColorRect.new()
	_top_bar.color = Color.BLACK
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_fx.add_child(_top_bar)

	_bottom_bar = ColorRect.new()
	_bottom_bar.color = Color.BLACK
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_fx.add_child(_bottom_bar)

	_set_bars(0.0)
	fx_parent.add_child(_fx)


## World-space prop: one ColorRect that plays the takraw ball / spike blast
## (sky_rally) or the ground shockwave (slam). Lives in the scene canvas so it
## inherits the camera zoom like the fighters do.
func _build_world_fx(fx_parent: Node) -> void:
	_world_fx = Node2D.new()
	_ball = ColorRect.new()
	_ball.color = BALL_COLOR
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ball.visible = false
	_world_fx.add_child(_ball)
	fx_parent.add_child(_world_fx)
