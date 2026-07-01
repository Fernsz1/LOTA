extends Node2D
## 4.1 — Training scene root. Two isolated arenas split by a mid-stage wall.
## Left arena: P1 (human) vs P1Dummy. Right arena: P2Dummy vs P2 (human).
## The wall blocks both projectiles and physical movement.

const FLOOR_Y: float = 560.0
const LEFT_WALL_X: float = 50.0
const RIGHT_WALL_X: float = 1230.0
const WALL_X: float = 640.0

@onready var _overlay: Node = $DebugOverlay
@onready var _hud: Node = $TrainingHUD
@onready var _p1: CharacterController = $P1
@onready var _p1_dummy: CharacterController = $P1Dummy
@onready var _p2_dummy: CharacterController = $P2Dummy
@onready var _p2: CharacterController = $P2

const PROJECTILE_SCENE := preload("res://scenes/projectile.tscn")
var _projectiles: Array[Projectile] = []


func _ready() -> void:
	process_physics_priority = 1
	Input.use_accumulated_input = false
	# Each arena uses its own half of the stage; the wall is the inner boundary.
	_p1.setup(FLOOR_Y, LEFT_WALL_X, WALL_X, _overlay)
	_p1_dummy.setup(FLOOR_Y, LEFT_WALL_X, WALL_X, _overlay)
	_p2_dummy.setup(FLOOR_Y, WALL_X, RIGHT_WALL_X, _overlay)
	_p2.setup(FLOOR_Y, WALL_X, RIGHT_WALL_X, _overlay)
	# owner_index: 1=P1→P1Dummy, 2=P1Dummy→P1, 3=P2Dummy→P2, 4=P2→P2Dummy
	_p1.projectile_requested.connect(_on_projectile_requested.bind(1))
	_p1_dummy.projectile_requested.connect(_on_projectile_requested.bind(2))
	_p2_dummy.projectile_requested.connect(_on_projectile_requested.bind(3))
	_p2.projectile_requested.connect(_on_projectile_requested.bind(4))


func _physics_process(_delta: float) -> void:
	_update_facing()
	_resolve_combat()
	_resolve_projectiles()
	_resolve_pushboxes()
	var max_hp: float = float(CharacterController.MAX_HEALTH)
	_hud.set_health(1, _p1.health / max_hp)
	_hud.set_health(2, _p1_dummy.health / max_hp)
	_hud.set_health(3, _p2_dummy.health / max_hp)
	_hud.set_health(4, _p2.health / max_hp)
	# Live move readout for the two human players
	_hud.set_move_readout(1, _p1.get_current_move(), _p1.get_frame_in_state())
	_hud.set_move_readout(2, _p2.get_current_move(), _p2.get_frame_in_state())


func _update_facing() -> void:
	_p1.facing = 1 if _p1_dummy.position.x > _p1.position.x else -1
	_p1_dummy.facing = 1 if _p1.position.x > _p1_dummy.position.x else -1
	_p2_dummy.facing = 1 if _p2.position.x > _p2_dummy.position.x else -1
	_p2.facing = 1 if _p2_dummy.position.x > _p2.position.x else -1


func _resolve_combat() -> void:
	if not (_p1.is_frozen() or _p1_dummy.is_frozen()):
		_try_hit(_p1, _p1_dummy)
		_try_hit(_p1_dummy, _p1)
	if not (_p2_dummy.is_frozen() or _p2.is_frozen()):
		_try_hit(_p2_dummy, _p2)
		_try_hit(_p2, _p2_dummy)


func _try_hit(attacker: CharacterController, defender: CharacterController) -> void:
	var move: MoveData = attacker.get_active_move()
	if move == null:
		return
	var overlapping: bool = CombatBoxes.overlaps(attacker.get_hitboxes(), defender.get_hurtboxes())
	var guarding: bool = HitResolver.is_guarding(defender.fsm_state(), defender.is_holding_back())
	var outcome: int = HitResolver.classify(overlapping, defender.is_invulnerable(), guarding)
	if outcome == HitResolver.Outcome.NONE:
		return
	attacker.mark_move_hit()
	attacker.apply_hitstop(move.hitstop)
	defender.apply_hitstop(move.hitstop)
	var push_dir: float = signf(defender.position.x - attacker.position.x)
	if push_dir == 0.0:
		push_dir = float(attacker.facing)
	if outcome == HitResolver.Outcome.BLOCK:
		defender.apply_block(move, push_dir)
	else:
		defender.apply_hit(move, push_dir)
	# 4.2 — frame advantage: stun - frames remaining for attacker after contact.
	var fis: int = attacker.get_frame_in_state()
	var remaining: int = move.total() - fis   # frames attacker still has in this attack
	var stun: int = move.blockstun if outcome == HitResolver.Outcome.BLOCK else move.hitstun
	var adv: int = stun - remaining
	var side: int = 1 if (attacker == _p1 or attacker == _p1_dummy) else 2
	_hud.show_advantage(side, adv)


func _on_projectile_requested(data: ProjectileData, origin: Vector2,
		facing: int, owner_index: int) -> void:
	for p in _projectiles:
		if p.owner_index == owner_index and not p.is_expired():
			return
	var proj: Projectile = PROJECTILE_SCENE.instantiate()
	add_child(proj)
	proj.setup(data, origin, facing, owner_index)
	_projectiles.append(proj)


func _resolve_projectiles() -> void:
	# owner→target map: 1→P1Dummy, 2→P1, 3→P2, 4→P2Dummy
	var targets: Array[CharacterController] = [_p1_dummy, _p1, _p2, _p2_dummy]
	var owners: Array[CharacterController] = [_p1, _p1_dummy, _p2_dummy, _p2]
	for proj in _projectiles:
		if proj.is_expired():
			continue
		var owner: CharacterController = owners[proj.owner_index - 1]
		var defender: CharacterController = targets[proj.owner_index - 1]
		if owner.is_frozen() or defender.is_frozen():
			continue
		proj.step()
		# Wall blocks projectiles: left-side owners can't cross right; right-side can't cross left.
		if (proj.owner_index <= 2 and proj.position.x >= WALL_X) \
				or (proj.owner_index >= 3 and proj.position.x <= WALL_X):
			proj.expire()
			continue
		var overlapping: bool = CombatBoxes.overlaps(proj.get_hitboxes(), defender.get_hurtboxes())
		var guarding: bool = HitResolver.is_guarding(defender.fsm_state(), defender.is_holding_back())
		var outcome: int = HitResolver.classify(overlapping, defender.is_invulnerable(), guarding)
		if outcome == HitResolver.Outcome.NONE:
			continue
		var push_dir: float = signf(defender.position.x - proj.position.x)
		if push_dir == 0.0:
			push_dir = float(proj.facing)
		defender.apply_hitstop(proj.data.hitstop)
		if outcome == HitResolver.Outcome.BLOCK:
			defender.apply_block_proj(proj.data, push_dir)
		else:
			defender.apply_hit_proj(proj.data, push_dir)
		proj.expire()
	var alive: Array[Projectile] = []
	for proj in _projectiles:
		if proj.is_expired():
			proj.queue_free()
		else:
			alive.append(proj)
	_projectiles = alive


## Live projectile hitboxes for the debug renderer (combat_debug.gd).
func get_projectile_hitboxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for proj in _projectiles:
		if not proj.is_expired():
			out.append_array(proj.get_hitboxes())
	return out


func _resolve_pushboxes() -> void:
	_resolve_pair(LEFT_WALL_X, WALL_X, _p1, _p1_dummy)
	_resolve_pair(WALL_X, RIGHT_WALL_X, _p2_dummy, _p2)


func _resolve_pair(left_bound: float, right_bound: float,
		a: CharacterController, b: CharacterController) -> void:
	var dx: float = b.position.x - a.position.x
	var min_dist: float = CharacterController.PUSH_W
	if absf(dx) < min_dist:
		var a_air: bool = CharacterStateMachine.is_airborne(a.fsm_state())
		var b_air: bool = CharacterStateMachine.is_airborne(b.fsm_state())
		if a_air and b_air:
			a._fsm.on_launched()
			b._fsm.on_launched()
			return
		elif a_air or b_air:
			return
	if absf(dx) >= min_dist:
		return
	var push: float = minf((min_dist - absf(dx)) * 0.5, 8.0)
	var dir: float = 1.0 if dx >= 0.0 else -1.0
	var half_w: float = CharacterController.PUSH_W * 0.5
	var min_x: float = left_bound + half_w
	var max_x: float = right_bound - half_w
	a.position.x -= push * dir
	b.position.x += push * dir
	if a.position.x < min_x:
		b.position.x += min_x - a.position.x
		a.position.x = min_x
	elif a.position.x > max_x:
		b.position.x -= a.position.x - max_x
		a.position.x = max_x
	if b.position.x < min_x:
		a.position.x += min_x - b.position.x
		b.position.x = min_x
	elif b.position.x > max_x:
		a.position.x -= b.position.x - max_x
		b.position.x = max_x
	a.position.x = clampf(a.position.x, min_x, max_x)
	b.position.x = clampf(b.position.x, min_x, max_x)
