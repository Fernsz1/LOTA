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

	# taking damage raises the flash overlay; main bar snaps instantly (7.4:
	# LoL-style), the trail bar is left at the old value to drain down
	hud.set_health(1, 1.0)
	hud.snap()
	hud.set_health(1, 0.6)   # a drop -> flash
	_check(hud._flash[1].modulate.a > 0.0, "damage raises P1 hit-flash")
	_check(is_equal_approx(hud._health[1].value, 60.0), "P1 health bar snaps instantly to 60")
	_check(is_equal_approx(hud._health_trail[1].value, 100.0),
			"P1 health trail holds the old value (100) right after the drop")
	_check(hud._hp_trail_tween[1] != null, "a drop starts the trail drain tween")
	hud.snap()
	_check(is_equal_approx(hud._health[1].value, 60.0), "snap keeps P1 health at target")
	_check(is_equal_approx(hud._health_trail[1].value, 60.0), "snap catches the trail bar up to target")

	# a gain (no damage) keeps the trail in sync — no orange sliver to show
	hud.set_health(2, 0.5)
	hud.snap()
	hud.set_health(2, 0.8)
	_check(is_equal_approx(hud._health_trail[2].value, 80.0),
			"a health increase syncs the trail immediately (nothing to peel off)")

	# 7.4 fix: the P1/P2 fill art is pre-colored (blue/red), so tinting it
	# orange via modulate would multiply against those pixels and render a
	# DIFFERENT effective hue per side. All four trail bars must share one
	# neutral (white) texture so the same orange modulate looks identical
	# everywhere regardless of which side's fill they sit behind.
	_check(hud._health_trail[1].texture_progress == hud._health_trail[2].texture_progress
			and hud._health_trail[1].texture_progress == hud._meter_trail[1].texture_progress
			and hud._health_trail[1].texture_progress == hud._meter_trail[2].texture_progress,
			"all four trail bars share one neutral texture (consistent orange both sides)")
	var trail_img: Image = hud._health_trail[1].texture_progress.get_image()
	_check(trail_img.get_pixel(0, 0) == Color.WHITE, "the shared trail texture is neutral white")

	# meter below full: player fill, ready hidden, blink stopped. 7.4: the
	# recharge bar renders through the recolor shader tinted brand orange —
	# the SAME orange regardless of P1(blue art)/P2(red art) source.
	hud.set_meter(1, 0.4)
	hud.snap()
	_check(is_equal_approx(hud._meter[1].value, 40.0), "P1 meter snaps to 40")
	_check(is_equal_approx(hud._super_ready[1].modulate.a, 0.0), "P1 SUPER READY hidden (alpha 0) below full")
	_check(hud._meter[1].material == hud._meter_material[1], "P1 meter recolor shader active while charging")
	_check(hud._meter_material[1].get_shader_parameter("tint") == hud.PLAYER_ACCENT,
			"P1 meter tint is the brand orange while charging")

	# meter full: green fill swap + ready shown + blink running. 7.4: the
	# ready texture is its OWN true green art — the shader must be OFF here,
	# or the white-ish default would flatten it toward grayscale.
	hud.set_meter(1, 1.0)
	_check(hud._super_ready[1].modulate.a > 0.0, "P1 SUPER READY shown (alpha>0) at full")
	_check(hud._meter[1].texture_progress == hud.METER_FILL_READY, "P1 meter fill swaps to green at full")
	_check(hud._meter[1].material == null, "P1 meter recolor shader OFF at full (true green, un-tinted)")
	_check(hud._blink[1] != null and hud._blink[1].is_running(), "P1 blink tween runs while full")

	# dropping below full stops the blink and re-arms the recolor shader
	hud.set_meter(1, 0.9)
	_check(hud._blink[1] == null, "P1 blink stops below full")
	_check(hud._meter[1].material == hud._meter_material[1],
			"P1 meter recolor shader re-armed after dropping below full")

	# timer color threshold
	hud.set_timer(30)
	_check(hud._timer.label_settings.font_color == hud.TIMER_OK, "timer yellow above warn")
	hud.set_timer(9)
	_check(hud._timer.label_settings.font_color == hud.TIMER_LOW, "timer red at/below warn")
	_check(hud._timer.text == "09", "timer zero-pads")

	# round pips: 7.4 fix — always PLAYER_ACCENT (orange), never the picked
	# character's own color, so a won pip reads the same regardless of who's
	# playing (previously it was recolored to whatever CharacterData.color
	# set_fighter last received — a different color every match).
	hud.set_rounds(1, 1)
	_check(hud._pips[1][0].color == hud.PLAYER_ACCENT, "P1 pip0 filled with the fixed player accent")
	_check(hud._pips[1][1].color == hud.PIP_OFF, "P1 pip1 stays dim")

	# set_fighter: name text always PLAYER_ACCENT (7.4 fix — never recolored
	# to the picked character), but the HEALTH BAR's recolor-shader tint DOES
	# track the character's own signature color (also 7.4 — this is the part
	# the user actually wants dynamic).
	hud.set_fighter(1, "ARNIS FIGHTER", Color(0.165, 0.659, 1, 1))
	_check(hud._name[1].text == "ARNIS FIGHTER", "P1 name from data")
	_check(hud._name[1].label_settings.font_color == hud.PLAYER_ACCENT,
			"P1 name stays the fixed player accent regardless of the character's own color")
	_check(hud._health_material[1].get_shader_parameter("tint") == Color(0.165, 0.659, 1, 1),
			"P1 health bar recolor-shader tint tracks the fighter's own signature color")
	_check(hud._portrait_material[1].get_shader_parameter("tint") == Color(0.165, 0.659, 1, 1),
			"P1 portrait-frame recolor-shader tint also tracks the fighter's own signature color")

	# timer/round branding: 7.4 fix — both now the same brand orange as the
	# name/pips (TIMER_OK was previously an unrelated gold); TIMER_LOW is kept
	# as a deliberate low-time danger cue, not a branding color.
	_check(hud.TIMER_OK == hud.PLAYER_ACCENT, "timer's normal color is the brand orange")

	# archetype "Tag" chips (e.g. "TECHNICAL / ZONER") are hidden per request —
	# node kept (not deleted) so a future per-character archetype line is a
	# one-line visible=true away, but nothing renders today.
	_check(not hud.get_node("HUD/P1/Tag").visible, "P1 archetype tag is hidden")
	_check(not hud.get_node("HUD/P2/Tag").visible, "P2 archetype tag is hidden")

	# 7.4 fix: the small persistent round counter (distinct from the big
	# announce() line) was never wired to anything — stuck at the .tscn's
	# baked "ROUND 1" forever.
	hud.set_round(3)
	_check(hud._round.text == "ROUND 3", "set_round updates the persistent round counter")

	# announce passthrough
	hud.announce("K.O.")
	_check(hud._announce.text == "K.O.", "announce sets text")

	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
