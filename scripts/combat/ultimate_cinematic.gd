class_name UltimateCinematic
extends RefCounted
## 7.3 — Cinematic ultimate (Jerb: "Iron Barrage — The Four Corners").
## Scene-owned, like ThrowSequencer: the match scene calls try_start() each frame
## and then step() once per physics frame until it returns true.
##
## Flow: on the first frame of a move flagged is_cinematic, both fighters are
## locked (is_frozen() → hits, throws, projectiles and the round timer all
## pause), the HUD is hidden, letterbox bars slide in and the camera zooms on
## the attacker. He runs to the victim and lands his four moves — jab, heavy,
## skill, then the ultimate itself — each with a stretched slow-motion windup
## and an impact flash + camera shake. The finisher flashes white, launches the
## victim across the stage into KNOCKDOWN, and the camera pulls back out as the
## HUD returns. The victim cannot act at any point.
##
## Slow motion is choreographic: everything else in the match is frozen, so
## stretching the windup frame counts reads as slowmo without touching
## Engine.time_scale (no global state to restore, no pause-menu interactions).

const CSM := preload("res://scripts/fsm/character_state_machine.gd")

# --- Choreography (frames @60Hz) ---
const ZOOM_IN_FRAMES: int = 36
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
const LAUNCH_FRAMES: int = 18        # victim flies back before the knockdown pop
const ZOOM_OUT_FRAMES: int = 32

const PULLBACK: float = 10.0         # attacker lean-back depth during windup
const LUNGE: float = 36.0            # attacker thrust depth past his anchor
const IMPACT_NUDGE: float = 8.0      # victim shoved back per non-final hit
const LAUNCH_SPEED: float = 14.0     # victim flyback px/frame at launch start
const LAUNCH_POP_Y: float = -7.0     # finisher vertical pop (falls into KNOCKDOWN)

const FOCUS_ZOOM: float = 2.0
const FINAL_ZOOM: float = 2.4        # extra push-in on the finisher windup
const FOCUS_Y: float = 470.0         # camera y while zoomed (fighters at floor 560)
const HOME_POS := Vector2(640, 360)  # identity view for the 1280x720 canvas
const BAR_H: float = 70.0            # letterbox bar height

# Damage split across hits 1-3 (fractions of move.damage); the finisher takes
# the remainder so the total always equals the authored ultimate damage.
const HIT_FRACTIONS: Array[float] = [0.15, 0.2, 0.25]

enum Phase { ZOOM_IN, RUN, WINDUP, THRUST, HOLD, RECOVER, LAUNCH, ZOOM_OUT }

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

var _phase: int = Phase.ZOOM_IN
var _t: int = 0                     # frames in the current phase
var _hit: int = 0                   # 0..3
var _hit_damages: Array[int] = []
var _atk_base_x: float = 0.0        # attacker anchor while striking
var _victim_start_y: float = 0.0    # eased to the floor during ZOOM_IN
var _shake: float = 0.0
var _zoom_out_from_pos: Vector2 = Vector2.ZERO
var _zoom_out_from_zoom: float = 1.0
var _launch_vel: float = 0.0
var _done: bool = false


## Detect + begin a cinematic ultimate this frame. Returns a live sequencer, or
## null. Fires only on the move's entry frame (frame_in_state == 0), so a denied
## start (e.g. the scene skipped us during a live throw) degrades gracefully:
## the move simply resolves as the normal strike it also authors.
static func try_start(atk: CharacterController, def: CharacterController,
		camera: Camera2D, hud: CanvasLayer, fx_parent: Node,
		left_x: float, right_x: float) -> UltimateCinematic:
	var move: MoveData = atk.get_current_move()
	if move == null or not move.is_cinematic:
		return null
	if atk.fsm_state() != CSM.State.SKILL or atk.get_frame_in_state() != 0:
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
		Phase.LAUNCH:
			_step_launch(dir)
		Phase.ZOOM_OUT:
			_step_zoom_out()
	_decay_fx()
	return _done


func is_done() -> bool:
	return _done


# --- Phase steps ---

func _step_zoom_in() -> void:
	var e: float = _ease(_t / float(ZOOM_IN_FRAMES))
	var focus: Vector2 = _cam_clamp(Vector2(attacker.position.x, FOCUS_Y), FOCUS_ZOOM)
	_camera.position = HOME_POS.lerp(focus, e)
	_camera.zoom = Vector2.ONE * lerpf(1.0, FOCUS_ZOOM, e)
	_set_bars(BAR_H * e)
	# Ground a frozen airborne victim so the strikes line up at body height.
	victim.position.y = lerpf(_victim_start_y, _floor_y, e)
	if _t >= ZOOM_IN_FRAMES:
		_enter(Phase.RUN)


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


func _step_launch(dir: float) -> void:
	victim.position.x = _clamp_stage_x(victim.position.x + _launch_vel * dir)
	_launch_vel = maxf(2.0, _launch_vel * 0.88)
	var zoom: float = lerpf(FINAL_ZOOM, FOCUS_ZOOM, _t / float(LAUNCH_FRAMES))
	_follow(Vector2(victim.position.x, FOCUS_Y), 0.25, zoom)
	if _t >= LAUNCH_FRAMES:
		victim.apply_cinematic_finisher(_hit_damages[3], LAUNCH_POP_Y)
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


# --- Internals ---

func _begin(move: MoveData, fx_parent: Node) -> void:
	_floor_y = attacker.position.y   # attacker is grounded (attacks start grounded)
	_victim_start_y = victim.position.y
	attacker.begin_cinematic_lock()
	victim.begin_cinematic_lock()
	_hud.visible = false
	_split_damage(move.damage)
	_build_fx(fx_parent)


func _split_damage(total: int) -> void:
	_hit_damages.clear()
	var spent: int = 0
	for f in HIT_FRACTIONS:
		var d: int = int(total * f)
		_hit_damages.append(d)
		spent += d
	_hit_damages.append(maxi(0, total - spent))   # finisher takes the remainder


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


func _enter(phase: int) -> void:
	_phase = phase
	_t = 0


func _finish() -> void:
	_camera.position = HOME_POS
	_camera.zoom = Vector2.ONE
	_camera.offset = Vector2.ZERO
	_hud.visible = true
	if _fx != null:
		_fx.queue_free()
		_fx = null
	_done = true


func _mid_x() -> float:
	return (attacker.position.x + victim.position.x) * 0.5


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
