extends SceneTree
## Headless smoke tests for the combat HUD (2.6). Instantiates the real scene and
## drives the public interface; asserts node values update. Cosmetic tweens are
## made deterministic via snap(). Run: godot --headless --script res://tests/test_match_hud.gd

const HUD_SCENE := preload("res://scenes/match_hud.tscn")

var _checks := 0
var _failures := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var hud = HUD_SCENE.instantiate()  # untyped: member access is dynamic (avoids Node._ready() static collision)
	get_root().add_child(hud)
	await process_frame  # let NOTIFICATION_READY fire so @onready node refs populate

	# health: setter + snap drives the bar value
	hud.set_health(1, 0.5)
	hud.set_health(2, 0.25)
	hud.snap()
	_check(is_equal_approx(hud._health[1].value, 50.0), "P1 health bar -> 50")
	_check(is_equal_approx(hud._health[2].value, 25.0), "P2 health bar -> 25")

	# taking damage raises the flash overlay; snap kills the drain tween
	hud.set_health(1, 1.0)
	hud.snap()
	hud.set_health(1, 0.6)   # a drop -> flash
	_check(hud._flash[1].modulate.a > 0.0, "damage raises P1 hit-flash")
	hud.snap()
	_check(is_equal_approx(hud._health[1].value, 60.0), "snap jumps P1 health to target mid-drain")

	# meter below full: player fill, ready hidden, blink stopped
	hud.set_meter(1, 0.4)
	hud.snap()
	_check(is_equal_approx(hud._meter[1].value, 40.0), "P1 meter snaps to 40")
	_check(not hud._super_ready[1].visible, "P1 SUPER READY hidden below full")

	# meter full: green fill swap + ready shown + blink running
	hud.set_meter(1, 1.0)
	_check(hud._super_ready[1].visible, "P1 SUPER READY shown at full")
	_check(hud._meter[1].texture_progress == hud.METER_FILL_READY, "P1 meter fill swaps to green at full")
	_check(hud._blink[1] != null and hud._blink[1].is_running(), "P1 blink tween runs while full")

	# dropping below full stops the blink
	hud.set_meter(1, 0.9)
	_check(hud._blink[1] == null, "P1 blink stops below full")

	# timer color threshold
	hud.set_timer(30)
	_check(hud._timer.label_settings.font_color == hud.TIMER_OK, "timer yellow above warn")
	hud.set_timer(9)
	_check(hud._timer.label_settings.font_color == hud.TIMER_LOW, "timer red at/below warn")
	_check(hud._timer.text == "09", "timer zero-pads")

	# round pips
	hud.set_rounds(1, 1)
	_check(hud._pips[1][0].color == hud._accent[1], "P1 pip0 filled with accent")
	_check(hud._pips[1][1].color == hud.PIP_OFF, "P1 pip1 stays dim")

	# set_fighter drives name + accent
	hud.set_fighter(1, "ARNIS FIGHTER", Color(0.165, 0.659, 1, 1))
	_check(hud._name[1].text == "ARNIS FIGHTER", "P1 name from data")
	_check(hud._name[1].label_settings.font_color == Color(0.165, 0.659, 1, 1), "P1 name color from data")

	# announce passthrough
	hud.announce("K.O.")
	_check(hud._announce.text == "K.O.", "announce sets text")

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
