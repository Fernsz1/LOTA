extends Node2D
## Main scene root. Hosts stage constants, spawns two player boxes, and owns all
## cross-character logic (pushbox separation, facing). Runs at physics priority 1
## so _physics_process fires AFTER both CharacterControllers (priority 0) have
## moved for this tick.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0

@onready var _overlay: Node = $DebugOverlay
@onready var _p1: CharacterController = $P1
@onready var _p2: CharacterController = $P2
@onready var _background: ColorRect = $Background
@onready var _floor: ColorRect = $Floor

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
var _projectiles: Array[Projectile] = []
var _throw: ThrowSequencer = null   # 6.4 — the one live throw (only two fighters)


func _ready() -> void:
	# Run AFTER child controllers so pushbox/facing logic sees this tick's positions.
	process_physics_priority = 1
	# Each input event dispatched immediately — reduces latency on high-Hz displays.
	Input.use_accumulated_input = false
	# Character-select picks (if any) override the .tscn-authored defaults. Absent
	# when this scene is run directly (e.g. F6 in the editor) — the tscn's own
	# character_data/box_color still apply in that case.
	if MatchSelection.p1_data != null:
		_p1.set_character(MatchSelection.p1_data, MatchSelection.p1_color)
	if MatchSelection.p2_data != null:
		_p2.set_character(MatchSelection.p2_data, MatchSelection.p2_color)
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
	_resolve_combat()
	_resolve_throws()     # 6.4 — after strikes (a same-frame strike beats a grab)
	_resolve_projectiles()
	# Pushbox separation pauses during a throw: the hold offset keeps the pair
	# legal, but the deep-overlap bounce would otherwise shove the victim out
	# of the attacker's hands on a point-blank connect.
	if _throw == null:
		_resolve_pushboxes()


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
		defender.end_counter()
		return
	attacker.apply_hitstop(move.hitstop)                      # freeze BOTH (feel-reference §4)
	defender.apply_hitstop(move.hitstop)
	var push_dir: float = signf(defender.position.x - attacker.position.x)
	if push_dir == 0.0:
		push_dir = float(attacker.facing)                    # perfectly overlapped → use facing
	if outcome == HitResolver.Outcome.BLOCK:
		defender.apply_block(move, push_dir)
	else:
		defender.apply_hit(move, push_dir)


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
