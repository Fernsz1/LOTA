extends Node2D
## Main scene root. Hosts stage constants, spawns two player boxes, and owns all
## cross-character logic (pushbox separation, facing). Runs at physics priority 1
## so _physics_process fires AFTER both CharacterControllers (priority 0) have
## moved for this tick.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0

# 7.3 — dynamic fight camera: frames both fighters like a classic fighting-game
# camera — pushed in on the action when they're close, pulling back out as they
# part, never showing past the 1280x720 canvas. The cinematic ultimate owns the
# camera while one is live.
const CAM_MARGIN: float = 130.0      # world px kept beyond the fighters' midpoint gap
const CAM_MAX_ZOOM: float = 2.1      # closest push-in (point-blank fighters)
const CAM_FLOOR_PAD: float = 70.0    # world px kept visible below the floor line
const CAM_HEAD_PAD: float = 110.0    # px above a fighter's feet that must stay framed
const CAM_POS_WEIGHT: float = 0.10   # per-physics-frame smoothing
const CAM_ZOOM_WEIGHT: float = 0.08

# Skill-move camera punch: a brief, slight extra push-in layered on top of the
# dynamic zoom above when a fighter's skill (not ultimate — SKILL is a shared
# FSM state) starts, decaying back out on its own over the following frames.
const SKILL_ZOOM_PUNCH: float = 0.18    # extra zoom added on the skill's first frame
const SKILL_ZOOM_DECAY: float = 0.12    # per-physics-frame falloff back to 0

@onready var _overlay: Node = $DebugOverlay
@onready var _combat_debug: Node = $CombatDebug
@onready var _p1: CharacterController = $P1
@onready var _p2: CharacterController = $P2
@onready var _background: ColorRect = $Background
@onready var _floor: ColorRect = $Floor
@onready var _camera: Camera2D = $Camera
@onready var _match_hud: CanvasLayer = $MatchHUD
@onready var _match_manager: Node = $MatchManager

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
var _projectiles: Array[Projectile] = []
var _throw: ThrowSequencer = null   # 6.4 — the one live throw (only two fighters)
var _ultimate: UltimateCinematic = null   # 7.3 — the one live cinematic ultimate
var _zoom_punch: float = 0.0   # current skill-camera-punch bias (see SKILL_ZOOM_PUNCH)


func _ready() -> void:
	# Run AFTER child controllers so pushbox/facing logic sees this tick's positions.
	process_physics_priority = 1
	# Each input event dispatched immediately — reduces latency on high-Hz displays.
	Input.use_accumulated_input = false
	# Both debug overlays (F1 hitboxes, F2 frame/state panel) stay OFF by default
	# in a real match — forced here rather than trusting only the .tscn's baked
	# `visible = false`, since CombatDebug's own _ready() reads `visible` to seed
	# its `_enabled` toggle state; this guarantees both are in sync. The F1/F2
	# hotkeys still work for dev use — this only affects the default state.
	_overlay.visible = false
	_combat_debug.visible = false
	# Character-select picks (if any) override the .tscn-authored defaults. Absent
	# when this scene is run directly (e.g. F6 in the editor) — the tscn's own
	# character_data/box_color still apply in that case.
	if MatchSelection.p1_data != null:
		_p1.set_character(MatchSelection.p1_data, MatchSelection.p1_color)
	if MatchSelection.p2_data != null:
		_p2.set_character(MatchSelection.p2_data, MatchSelection.p2_color)
	# 7.4 fix: push the (now-correct) fighter data to the HUD. MatchManager is
	# an earlier sibling under this same node, so its own _ready() already ran
	# — BEFORE the set_character() calls above — and would have read stale
	# .tscn-baked data if it pushed the HUD itself. Calling it from here,
	# after the override, is what actually fixes the ordering.
	_match_manager.refresh_fighters()
	# 7.2 — stage-select pick (if any) overrides the .tscn-authored background/floor.
	if MatchSelection.stage_data != null:
		_background.color = MatchSelection.stage_data.background_color
		_floor.color = MatchSelection.stage_data.floor_color
	_p1.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)
	_p2.setup(FLOOR_Y, LEFT_WALL_X, RIGHT_WALL_X, _overlay)
	_p1.projectile_requested.connect(_on_projectile_requested.bind(1))
	_p2.projectile_requested.connect(_on_projectile_requested.bind(2))


func _physics_process(_delta: float) -> void:
	_update_facing()      # fresh facing first: combat reads back-direction + mirrors boxes
	_resolve_ultimate_cinematic()   # 7.3 — before combat: the lock freezes everything below
	_resolve_combat()
	_resolve_throws()     # 6.4 — after strikes (a same-frame strike beats a grab)
	_resolve_projectiles()
	# Pushbox separation pauses during a throw or a cinematic ultimate: the
	# scripted offsets keep the pair legal, but the deep-overlap bounce would
	# otherwise shove the fighters out of their choreographed positions.
	if _throw == null and _ultimate == null:
		_resolve_pushboxes()
	# Camera last: it frames this tick's final positions. The cinematic drives
	# the camera itself while live; on release it hands back mid-frame and the
	# dynamic camera lerps home from wherever the cutscene left it.
	if _ultimate == null:
		_update_skill_zoom_punch()
		_update_camera()


# Skill-move camera punch: re-arms to SKILL_ZOOM_PUNCH the instant either fighter's
# move_skill starts (frame_in_state 0 of the shared SKILL state — checking against
# move_skill specifically excludes the ultimate, which reuses the same FSM state),
# then decays back to 0 every other frame. _update_camera() adds this on top of its
# own distance-based zoom, so the skill gets a slight push-in that eases back out
# on its own as the punch decays — no separate "zoom out" step needed.
func _update_skill_zoom_punch() -> void:
	var skill_started: bool = \
			(_p1.get_current_move() == _p1.move_skill and _p1.get_frame_in_state() == 0) \
			or (_p2.get_current_move() == _p2.move_skill and _p2.get_frame_in_state() == 0)
	if skill_started:
		_zoom_punch = SKILL_ZOOM_PUNCH
	else:
		_zoom_punch = lerpf(_zoom_punch, 0.0, SKILL_ZOOM_DECAY)


# Fit-both framing: zoom is derived from the fighters' horizontal gap (plus
# margin), the camera sits on their midpoint, anchored so the floor stays in
# frame, rising when someone jumps toward the top edge. Everything is clamped
# to the canvas, so at zoom 1 this converges to the old fixed full-stage view.
func _update_camera() -> void:
	var half_needed: float = absf(_p2.position.x - _p1.position.x) * 0.5 + CAM_MARGIN
	var z: float = lerpf(_camera.zoom.x,
			clampf(640.0 / half_needed, 1.0, CAM_MAX_ZOOM) + _zoom_punch, CAM_ZOOM_WEIGHT)
	_camera.zoom = Vector2.ONE * z
	var half_w: float = 640.0 / z
	var half_h: float = 360.0 / z
	var top_y: float = minf(_p1.position.y, _p2.position.y) - CAM_HEAD_PAD
	var target := Vector2(
			(_p1.position.x + _p2.position.x) * 0.5,
			minf(FLOOR_Y + CAM_FLOOR_PAD - half_h, top_y + half_h))
	target.x = clampf(target.x, half_w, 1280.0 - half_w)
	target.y = clampf(target.y, half_h, 720.0 - half_h)
	_camera.position = _camera.position.lerp(target, CAM_POS_WEIGHT)


# 7.3 — Jerb's cinematic ultimate. Owns both fighters while live: starts on the
# first frame of a move flagged is_cinematic, steps once per physics frame
# (unconditionally — the lock itself is what reports frozen), and ends when the
# camera is home again. Never starts over a connected throw.
func _resolve_ultimate_cinematic() -> void:
	if _ultimate != null:
		if _ultimate.step():
			_ultimate = null
		return
	if _throw != null:
		return
	_ultimate = UltimateCinematic.try_start(_p1, _p2, _camera, _match_hud, self,
			LEFT_WALL_X, RIGHT_WALL_X)
	if _ultimate == null:
		_ultimate = UltimateCinematic.try_start(_p2, _p1, _camera, _match_hud, self,
				LEFT_WALL_X, RIGHT_WALL_X)


# Detect and resolve hits this frame (2.4). Runs after both controllers have moved
# (priority 1). While either fighter is frozen (hitstop) nothing resolves. Both
# attack directions are checked so a trade lands for both sides.
func _resolve_combat() -> void:
	if _p1.is_frozen() or _p2.is_frozen():
		return
	_try_hit(_p1, _p2)
	_try_hit(_p2, _p1)


func _try_hit(attacker: CharacterController, defender: CharacterController) -> void:
	var move: MoveData = attacker.get_active_move()
	if move == null:
		return
	var overlapping: bool = CombatBoxes.overlaps(attacker.get_hitboxes(), defender.get_hurtboxes())
	var guarding: bool = HitResolver.is_guarding(defender.fsm_state(), defender.is_holding_back())
	var outcome: int = HitResolver.classify(overlapping, defender.is_invulnerable(),
			guarding, defender.is_countering())
	if outcome == HitResolver.Outcome.NONE:
		return

	attacker.mark_move_hit()                                  # one hit per attack
	if outcome == HitResolver.Outcome.COUNTERED:
		# 6.2 — the stance answers the strike: the ATTACKER eats the counter's
		# payload (damage/knockdown/pushback via the normal apply_hit path) and
		# the defender is released to neutral. Hitstop is the COUNTER move's.
		var counter: MoveData = defender.get_current_move()
		attacker.apply_hitstop(counter.hitstop)
		defender.apply_hitstop(counter.hitstop)
		var away: float = signf(attacker.position.x - defender.position.x)
		if away == 0.0:
			away = -float(attacker.facing)
		attacker.apply_hit(counter, away)
		defender.on_damage_dealt(counter.damage)   # the counter-holder dealt the retaliation
		defender.end_counter()
		return
	attacker.apply_hitstop(move.hitstop)                      # freeze BOTH (feel-reference §4)
	defender.apply_hitstop(move.hitstop)
	var push_dir: float = signf(defender.position.x - attacker.position.x)
	if push_dir == 0.0:
		push_dir = float(attacker.facing)                    # perfectly overlapped → use facing
	if outcome == HitResolver.Outcome.BLOCK:
		defender.apply_block(move, push_dir)   # no meter on block (no chip in v1)
	else:
		defender.apply_hit(move, push_dir)
		attacker.on_damage_dealt(move.damage)


# 6.4 — grab detection + throw progression. One throw at a time (two fighters:
# the attacker is busy and the victim is held, so a second can't start). Frozen
# frames (hitstop) pause the sequence exactly like strike resolution.
func _resolve_throws() -> void:
	if _p1.is_frozen() or _p2.is_frozen():
		return
	if _throw != null:
		if _throw.step():
			_throw = null
		return
	_throw = ThrowSequencer.try_start(_p1, _p2)
	if _throw == null:
		_throw = ThrowSequencer.try_start(_p2, _p1)


# 3.2 — spawn one projectile, gated to ONE live per owner (fire-and-forget). If the
# owner already has a live projectile the request is dropped (the move still animated).
func _on_projectile_requested(data: ProjectileData, origin: Vector2, facing: int, owner_index: int) -> void:
	for p in _projectiles:
		if p.owner_index == owner_index and not p.is_expired():
			return
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	add_child(proj)
	proj.setup(data, origin, facing, owner_index)
	_projectiles.append(proj)


# 3.2 — move + resolve every live projectile vs the OPPONENT, reusing the 2.4 path.
# Frozen with the fighters during hitstop. Despawns on hit/block/range.
func _resolve_projectiles() -> void:
	if _p1.is_frozen() or _p2.is_frozen():
		return
	for proj in _projectiles:
		if proj.is_expired():
			continue
		proj.step()
		var defender: CharacterController = _p2 if proj.owner_index == 1 else _p1
		var overlapping: bool = CombatBoxes.overlaps(proj.get_hitboxes(), defender.get_hurtboxes())
		var guarding: bool = HitResolver.is_guarding(defender.fsm_state(), defender.is_holding_back())
		var outcome: int = HitResolver.classify(overlapping, defender.is_invulnerable(), guarding)
		if outcome == HitResolver.Outcome.NONE:
			continue
		var push_dir: float = signf(defender.position.x - proj.position.x)
		if push_dir == 0.0:
			push_dir = float(proj.facing)
		defender.apply_hitstop(proj.data.hitstop)   # defender only — thrower keeps acting (classic fireball)
		if outcome == HitResolver.Outcome.BLOCK:
			defender.apply_block_proj(proj.data, push_dir)
		else:
			defender.apply_hit_proj(proj.data, push_dir)
			var owner_ctl: CharacterController = _p1 if proj.owner_index == 1 else _p2
			owner_ctl.on_damage_dealt(proj.data.damage)
		proj.expire()
	# cull expired
	var alive: Array[Projectile] = []
	for proj in _projectiles:
		if proj.is_expired():
			proj.queue_free()
		else:
			alive.append(proj)
	_projectiles = alive


## 3.2 — live projectile hitboxes for the debug renderer (combat_debug.gd).
func get_projectile_hitboxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for proj in _projectiles:
		if not proj.is_expired():
			out.append_array(proj.get_hitboxes())
	return out


# Prevent horizontal overlap by pushing characters apart along X.
# Y is ignored so airborne characters can jump over each other freely.
# If a push hits a stage wall the surplus is transferred to the other character.
var _deep_overlap_frames: int = 0

func _resolve_pushboxes() -> void:
	var dx: float = _p2.position.x - _p1.position.x
	var min_dist: float = CharacterController.PUSH_W

	# Airborne collisions only happen if their standard pushboxes are horizontally overlapping
	if absf(dx) < min_dist:
		var p1_air: bool = CharacterStateMachine.is_airborne(_p1.fsm_state())
		var p2_air: bool = CharacterStateMachine.is_airborne(_p2.fsm_state())

		if p1_air and p2_air:
			_p1._fsm.on_launched()
			_p2._fsm.on_launched()
			return
		elif p1_air or p2_air:
			return
	
	# If a deep overlap happens (jumping player landing), temporarily increase 
	# the target separation distance so they bounce farther apart.
	if absf(dx) < min_dist * 0.6:
		_deep_overlap_frames = 12
		
	if _deep_overlap_frames > 0:
		_deep_overlap_frames -= 1
		min_dist = CharacterController.PUSH_W * 1.8

	if absf(dx) >= min_dist:
		return

	var raw_push: float = (min_dist - absf(dx)) * 0.5
	var push: float = minf(raw_push, 8.0)  # Faster but smooth push for Case 2
	var dir: float = 1.0 if dx >= 0.0 else -1.0  # P1 goes left, P2 goes right (or inverse)
	var half_w: float = CharacterController.PUSH_W * 0.5
	var min_x: float = LEFT_WALL_X + half_w
	var max_x: float = RIGHT_WALL_X - half_w

	_p1.position.x -= push * dir
	_p2.position.x += push * dir

	# Transfer wall overflow so a cornered character pushes the opponent instead.
	if _p1.position.x < min_x:
		_p2.position.x += min_x - _p1.position.x
		_p1.position.x = min_x
	elif _p1.position.x > max_x:
		_p2.position.x -= _p1.position.x - max_x
		_p1.position.x = max_x

	if _p2.position.x < min_x:
		_p1.position.x += min_x - _p2.position.x
		_p2.position.x = min_x
	elif _p2.position.x > max_x:
		_p1.position.x -= _p2.position.x - max_x
		_p2.position.x = max_x

	# Safety clamp in case both are simultaneously wall-pressed.
	_p1.position.x = clampf(_p1.position.x, min_x, max_x)
	_p2.position.x = clampf(_p2.position.x, min_x, max_x)


# Characters always face each other. Re-derived every frame from positions so
# it stays correct even if an air jump temporarily shifts relative sides.
func _update_facing() -> void:
	_p1.facing = 1 if _p2.global_position.x > _p1.global_position.x else -1
	_p2.facing = 1 if _p1.global_position.x > _p2.global_position.x else -1
