extends SceneTree
## Headless check: the 5 map-region StageData resources load with the right names.

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
	var expect := {
		"res://stages/bahay_kubo/bahay_kubo_data.tres": "Bahay Kubo Training Yard",
		"res://stages/mountain_festival/mountain_festival_data.tres": "Mountain Festival Grounds",
		"res://stages/barangay_ring/barangay_ring_data.tres": "Barangay Boxing Ring",
		"res://stages/heritage_plaza/heritage_plaza_data.tres": "Heritage Plaza",
		"res://stages/beach_court/beach_court_data.tres": "Beach Court at Dusk",
	}
	for path: String in expect:
		var sd: Resource = load(path)
		_check(sd != null, "loads %s" % path)
		_check(sd != null and sd.stage_name == expect[path], "stage_name == %s" % expect[path])
	print("\n%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
