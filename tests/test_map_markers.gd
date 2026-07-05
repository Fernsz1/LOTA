extends SceneTree

const Markers := preload("res://scenes/ui/map_select/map_markers.gd")

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var m: Node2D = Markers.new()
	get_root().add_child(m)
	m.build([
		{"gid": "Visayas", "pos": Vector2(600, 300), "color": Color("#6b4a9c")},
		{"gid": "Mindanao", "pos": Vector2(650, 500), "color": Color("#c0982f")},
	])
	ok(m.get_node_or_null("Visayas") != null, "beacon node created for Visayas")
	ok(m.get_node_or_null("Mindanao") != null, "beacon node created for Mindanao")
	var vis: Node2D = m.get_node("Visayas")
	ok(vis.position == Vector2(600, 300), "beacon positioned at screen centroid")

	m.set_color("Visayas", Color("#b154ff"))
	ok(m.marker_color("Visayas") == Color("#b154ff"), "set_color updates stored color")
	ok(m.marker_color("Mindanao") == Color("#c0982f"), "other marker unchanged")

	# rebuild replaces cleanly (idempotent)
	m.build([{"gid": "Visayas", "pos": Vector2(10, 10), "color": Color.WHITE}])
	var count := 0
	for c in m.get_children():
		count += 1
	ok(count == 1, "rebuild frees old beacons (got %d)" % count)

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
