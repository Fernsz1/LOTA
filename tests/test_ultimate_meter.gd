extends SceneTree
## Headless unit tests for UltimateMeter (spec: .local/2026-07-04 design doc).
## Run: godot --headless --path . --script res://tests/test_ultimate_meter.gd  (exit 0 = all pass)

const UM := preload("res://scripts/combat/ultimate_meter.gd")

var _checks := 0
var _failures := 0

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)
		printerr("FAIL: ", msg)

func _initialize() -> void:
	_test_starts_empty()
	_test_deal_rate()
	_test_take_rate_double()
	_test_cap()
	_test_full_gate()
	_test_consume()
	_test_fraction()
	_test_fill()
	_test_round_pacing()
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _test_starts_empty() -> void:
	var m := UM.new()
	_check(m.value == 0.0, "starts at 0")
	_check(not m.is_full(), "not full at 0")

func _test_deal_rate() -> void:
	var m := UM.new()
	m.gain_dealt(100)
	_check(is_equal_approx(m.value, 100 * UM.DEAL_RATE), "gain_dealt(100) == 100 * DEAL_RATE")

func _test_take_rate_double() -> void:
	var a := UM.new()
	var b := UM.new()
	a.gain_dealt(200)
	b.gain_taken(200)
	_check(is_equal_approx(b.value, 2.0 * a.value), "taking charges exactly 2x dealing")

func _test_cap() -> void:
	var m := UM.new()
	m.gain_taken(99999)
	_check(m.value == UM.MAX_METER, "gain clamps at MAX_METER")
	m.gain_dealt(500)
	_check(m.value == UM.MAX_METER, "no overfill past MAX_METER")

func _test_full_gate() -> void:
	var m := UM.new()
	m.gain_taken(990)   # 99.0 — just under full
	_check(not m.is_full(), "99 meter is not full")
	m.gain_taken(100)   # would exceed → clamps to exactly MAX_METER
	_check(m.is_full(), "reaching MAX_METER is full")

func _test_consume() -> void:
	var m := UM.new()
	m.fill()
	m.consume()
	_check(m.value == 0.0, "consume empties the bar")
	_check(not m.is_full(), "not full after consume")

func _test_fraction() -> void:
	var m := UM.new()
	_check(m.fraction() == 0.0, "fraction 0 when empty")
	m.gain_taken(500)   # 50.0
	_check(is_equal_approx(m.fraction(), 0.5), "fraction 0.5 at half")
	m.fill()
	_check(m.fraction() == 1.0, "fraction 1 when full")

func _test_fill() -> void:
	var m := UM.new()
	m.fill()
	_check(m.is_full(), "fill() sets full (training mode)")

func _test_round_pacing() -> void:
	# Spec balance model: dealing ~1000 while taking ~500 lands exactly on a full
	# bar (~1 ultimate per player per round with even trading).
	var m := UM.new()
	m.gain_dealt(1000)
	m.gain_taken(500)
	_check(m.is_full(), "deal 1000 + take 500 == exactly full")
