extends Node
## Round & match orchestration (2.6). Runs after main.gd (priority 2) so it reads
## post-resolution health each frame. Drives the pure MatchState, detects KO/timeout,
## handles round-end → reset → next round / match-end, and reflects to the HUD.

const RESET_DELAY: int = 90        # frames to hold on KO/result before the next round
const MATCH_END_HOLD: int = 150    # frames to hold on the final win before cutting to Results — longer beat than a round transition
const P1_SPAWN_X: float = 400.0
const P2_SPAWN_X: float = 880.0
const INTRO_FRAMES: int = 45       # how long "ROUND N" stays up at round start

@export var p1_path: NodePath
@export var p2_path: NodePath
@export var hud_path: NodePath

var _p1: CharacterController
var _p2: CharacterController
var _hud: Node
var _state: MatchState = MatchState.new()
var _delay: int = 0

func _ready() -> void:
	process_physics_priority = 2
	_p1 = get_node(p1_path)
	_p2 = get_node(p2_path)
	_hud = get_node(hud_path)
	push_fighter(_hud, 1, _p1.character_data)
	push_fighter(_hud, 2, _p2.character_data)
	_state.start_match()
	_reset_round()

# Maps a CharacterData (name + signature color) onto the HUD's fighter plate.
# Null-safe: falls back to "P1"/"P2" and the default accent when data is missing.
static func push_fighter(hud: Node, player: int, data) -> void:
	var fighter_name: String = "P%d" % player
	var color: Color = Color(0.165, 0.659, 1, 1) if player == 1 else Color(1, 0.231, 0.231, 1)
	if data != null:
		if data.character_name != "":
			fighter_name = data.character_name
		color = data.color
	hud.set_fighter(player, fighter_name, color)

func _physics_process(_delta: float) -> void:
	match _state.phase:
		MatchState.Phase.FIGHT:
			_fight()
		MatchState.Phase.ROUND_END:
			_round_end()
		MatchState.Phase.MATCH_END:
			_match_end()

func _fight() -> void:
	_update_bars()
	if _p1.is_frozen() or _p2.is_frozen():
		return                                   # paused during hitstop
	_state.tick_timer()
	_hud.set_timer(_state.seconds_left())
	if _state.time_left <= MatchState.ROUND_FRAMES - INTRO_FRAMES:
		_hud.announce("")                        # clear the round intro
	var winner: int = _winner_now()
	if winner != -1:
		_end_round(winner)

# Round winner: 1 / 2 player, 0 = draw, -1 = still going.
func _winner_now() -> int:
	var p1_dead: bool = _p1.health <= 0
	var p2_dead: bool = _p2.health <= 0
	if p1_dead and p2_dead:
		return 0
	if p2_dead:
		return 1
	if p1_dead:
		return 2
	if _state.time_up():
		# 6.3: raw-HP tiebreak, not percentage. With unequal maxes (e.g. Sofia 900)
		# a full-life fighter can lose a double-timeout to a higher-max fighter sitting
		# above her max. Accepted for v1 (timeouts are rare in a rushdown meta); the 8.2
		# balance pass reconsiders percentage-based if it ever matters.
		if _p1.health > _p2.health:
			return 1
		if _p2.health > _p1.health:
			return 2
		return 0
	return -1

func _end_round(winner: int) -> void:
	if winner != 1:
		_p1.force_ko()
	if winner != 2:
		_p2.force_ko()
	_state.record_round_win(winner)              # winner 0 → draw, no point, replay
	_hud.set_rounds(1, _state.p1_rounds)
	_hud.set_rounds(2, _state.p2_rounds)
	if _state.phase == MatchState.Phase.MATCH_END:
		var winner_name: String = MatchSelection.p1_name if _state.match_winner() == 1 else MatchSelection.p2_name
		Leaderboard.record_win(winner_name)
		_hud.announce("%s WINS" % winner_name)
		_delay = MATCH_END_HOLD
	else:
		_hud.announce("DRAW" if winner == 0 else "K.O.")
		_delay = RESET_DELAY

func _round_end() -> void:
	_update_bars()
	_delay -= 1
	if _delay <= 0:
		_reset_round()

func _match_end() -> void:
	_delay -= 1
	if _delay <= 0:
		MatchSelection.winner = _state.match_winner()
		get_tree().change_scene_to_file("res://scenes/match_result.tscn")

func _reset_round() -> void:
	_p1.reset_for_round(P1_SPAWN_X)
	_p2.reset_for_round(P2_SPAWN_X)
	_state.start_round()
	_update_bars()
	_hud.set_timer(_state.seconds_left())
	_hud.set_rounds(1, _state.p1_rounds)
	_hud.set_rounds(2, _state.p2_rounds)
	_hud.announce("ROUND %d" % (_state.p1_rounds + _state.p2_rounds + 1))

func _update_bars() -> void:
	# 6.3/6.4 — per-character max health (Sofia 900, Jacob 1150); bars are fractions of it.
	_hud.set_health(1, float(_p1.health) / float(_p1.get_max_health()))
	_hud.set_health(2, float(_p2.health) / float(_p2.get_max_health()))
	_hud.set_meter(1, _p1.get_meter_fraction())
	_hud.set_meter(2, _p2.get_meter_fraction())
