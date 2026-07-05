extends SceneTree

const UI := preload("res://scenes/ui/map_select/map_ui.gd")

var checks := 0
var failures := 0
var confirmed := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var ui: CanvasLayer = UI.new()
	get_root().add_child(ui)

	# standby state
	ui.set_state({"kicker": "STANDBY", "accent": Color("#4a5058"),
		"region_name": "SELECT YOUR ARENA", "region_no": "", "fighter": "—",
		"stage": "—", "story": "Hover a region…", "fighter_label": "[Selected Fighter Name]",
		"confirm_enabled": false})
	ok(ui.confirm_rect_contains(Vector2(-999, -999)) == false, "point far outside not in confirm rect")

	# confirm disabled -> click emits nothing
	ui.confirm_pressed.connect(func(): confirmed += 1)
	ui._on_confirm_click()
	ok(confirmed == 0, "disabled confirm ignores click")

	# selected state enables confirm
	ui.set_state({"kicker": "LOCKED IN", "accent": Color("#b154ff"),
		"region_name": "VISAYAS", "region_no": "(REGION 4)", "fighter": "SIKARAN",
		"stage": "HERITAGE PLAZA", "story": "Sikaran…", "fighter_label": "SIKARAN",
		"confirm_enabled": true})
	ui._on_confirm_click()
	ok(confirmed == 1, "enabled confirm emits confirm_pressed")

	# ribbon
	ui.show_ribbon("HERITAGE PLAZA")
	ok(ui.is_ribbon_visible(), "ribbon visible after show_ribbon")

	# a point inside the confirm button rect is detected
	ok(ui.confirm_rect_contains(ui.confirm_rect_centre()), "confirm centre is inside confirm rect")

	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
