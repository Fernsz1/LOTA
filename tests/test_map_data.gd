extends SceneTree
## Validates REGIONS metadata + the corrected region->stage mapping (regression
## for the Central/Visayas/Mindanao shuffle bug). Pure data — no scene needed.

const Data := preload("res://scenes/ui/map_select/map_manager.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

## The authoritative mapping from the handoff (.local/README.md META table).
const EXPECTED := {
	"NorthernLuzon": {"index": 1, "display": "NORTHERN LUZON", "fighter": "BUNO",
		"stage": "res://stages/mountain_festival/mountain_festival_data.tres"},
	"CentralLuzon":  {"index": 2, "display": "CENTRAL LUZON", "fighter": "DIRTY BOXING",
		"stage": "res://stages/barangay_ring/barangay_ring_data.tres"},
	"SouthernLuzon": {"index": 3, "display": "SOUTHERN LUZON", "fighter": "ARNIS",
		"stage": "res://stages/bahay_kubo/bahay_kubo_data.tres"},
	"Visayas":       {"index": 4, "display": "VISAYAS", "fighter": "SIKARAN",
		"stage": "res://stages/heritage_plaza/heritage_plaza_data.tres"},
	"Mindanao":      {"index": 5, "display": "MINDANAO", "fighter": "SEPAK TAKRAW",
		"stage": "res://stages/beach_court/beach_court_data.tres"},
}

func _init() -> void:
	ok(Data.REGIONS.size() == 5, "exactly 5 regions (got %d)" % Data.REGIONS.size())
	ok(Data.REGION_ORDER.size() == 5, "REGION_ORDER has 5 ids")

	var required := ["index", "display", "base", "neon", "neon_stroke",
		"fighter", "stage", "stage_label", "story"]
	for gid in EXPECTED:
		ok(Data.REGIONS.has(gid), "region present: " + gid)
		if not Data.REGIONS.has(gid):
			continue
		var r: Dictionary = Data.REGIONS[gid]
		for key in required:
			ok(r.has(key), "%s has key %s" % [gid, key])
		# corrected mapping (regression guard)
		ok(r["index"] == EXPECTED[gid]["index"], "%s index" % gid)
		ok(r["display"] == EXPECTED[gid]["display"], "%s display" % gid)
		ok(r["fighter"] == EXPECTED[gid]["fighter"], "%s fighter" % gid)
		ok(r["stage"] == EXPECTED[gid]["stage"], "%s stage path (shuffle regression)" % gid)
		ok(ResourceLoader.exists(r["stage"]), "%s stage .tres exists on disk" % gid)
		ok(r["base"] is Color and r["neon"] is Color and r["neon_stroke"] is Color,
			"%s colors are Color" % gid)
		ok((r["story"] as String).length() > 0, "%s has non-empty story" % gid)

	# REGION_ORDER is index-sorted and matches keys
	for i in Data.REGION_ORDER.size():
		var gid: String = Data.REGION_ORDER[i]
		ok(Data.REGIONS.has(gid), "REGION_ORDER[%d] is a real region" % i)
		ok(Data.REGIONS[gid]["index"] == i + 1, "REGION_ORDER[%d] index == %d" % [i, i + 1])

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
