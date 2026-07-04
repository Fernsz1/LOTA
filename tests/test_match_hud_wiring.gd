extends Node
## Verifies MatchManager pushes fighter identity into the HUD once. Uses a stub HUD
## so no full match scene is needed. Scene-based (not a bare --script SceneTree) so the
## project's autoloads register and match_manager.gd — which references MatchSelection /
## Leaderboard — compiles.
## Run: godot --headless --path . res://tests/test_match_hud_wiring.tscn

const MM := preload("res://scripts/match/match_manager.gd")
const CD := preload("res://scripts/character/character_data.gd")

var _checks := 0
var _failures := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)

class StubHUD:
	extends Node
	var fighters := {}
	func set_fighter(player: int, n: String, c: Color) -> void: fighters[player] = [n, c]
	func set_timer(_s: int) -> void: pass
	func set_rounds(_p: int, _w: int) -> void: pass
	func set_health(_p: int, _f: float) -> void: pass
	func set_meter(_p: int, _f: float) -> void: pass
	func announce(_t: String) -> void: pass

func _ready() -> void:
	# Focused check: the helper maps a controller's CharacterData to set_fighter.
	var hud := StubHUD.new()
	var d1 := CD.new(); d1.character_name = "ARNIS FIGHTER"; d1.color = Color(0.165, 0.659, 1, 1)
	var d2 := CD.new(); d2.character_name = "DIRTY BOXING FIGHTER"; d2.color = Color(1, 0.231, 0.231, 1)
	MM.push_fighter(hud, 1, d1)
	MM.push_fighter(hud, 2, d2)
	_check(hud.fighters[1][0] == "ARNIS FIGHTER", "P1 name pushed from data")
	_check(hud.fighters[1][1] == Color(0.165, 0.659, 1, 1), "P1 color pushed from data")
	_check(hud.fighters[2][0] == "DIRTY BOXING FIGHTER", "P2 name pushed from data")

	# Null-safe fallback: missing data -> default P#/accent.
	var hud2 := StubHUD.new()
	MM.push_fighter(hud2, 1, null)
	_check(hud2.fighters[1][0] == "P1", "null data falls back to P1")

	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
