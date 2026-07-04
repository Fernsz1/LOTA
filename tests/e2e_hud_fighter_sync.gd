extends Node
## 7.4 — Regression test for the character-data ordering bug: P1/P2,
## MatchHUD, and MatchManager are all SIBLINGS under Main, so sibling
## _ready() order follows scene-tree child order, not any cross-dependency.
## MatchManager used to read _p1.character_data / _p2.character_data in its
## OWN _ready() (which runs before Main's, since Main is the parent) — before
## Main._ready() had a chance to apply the MatchSelection override via
## set_character(). The HUD silently showed whichever characters main.tscn
## happens to bake in for P1/P2, never the actual character-select pick.
##
## This boots the REAL main.tscn with MatchSelection overridden to the
## OPPOSITE of main.tscn's baked defaults (P1=Jerb, P2=Rainne authored in the
## scene; here we assign P1=Rainne's data, P2=Jerb's) and asserts the HUD
## name labels reflect the OVERRIDE, not the scene's baked default.
## Run: godot --headless --path . res://tests/e2e_hud_fighter_sync.tscn

var _checks := 0
var _failures := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)


func _ready() -> void:
	var rainne_data: CharacterData = load("res://characters/rainne/rainne_data.tres")
	var jerb_data: CharacterData = load("res://characters/jerb/jerb_data.tres")
	# The swap: main.tscn bakes P1=Jerb / P2=Rainne. If the ordering bug were
	# still present, the HUD would show that baked pairing regardless of this
	# override.
	MatchSelection.p1_data = rainne_data
	MatchSelection.p1_color = rainne_data.color
	MatchSelection.p2_data = jerb_data
	MatchSelection.p2_color = jerb_data.color

	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	var hud: CanvasLayer = main.get_node("MatchHUD")
	_check(hud._name[1].text == "Rainne", "P1 HUD name reflects the MatchSelection override (Rainne), not the .tscn's baked Jerb")
	_check(hud._name[2].text == "Jerb", "P2 HUD name reflects the MatchSelection override (Jerb), not the .tscn's baked Rainne")
	_check(hud._health_material[1].get_shader_parameter("tint") == rainne_data.color,
			"P1 health-bar tint matches the overridden character's own color (Rainne)")
	_check(hud._health_material[2].get_shader_parameter("tint") == jerb_data.color,
			"P2 health-bar tint matches the overridden character's own color (Jerb)")

	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
