extends Sprite2D
## Randomized in-match arena backdrop. Node2D-based (not Control) because
## this lives directly under the fight scene's Node2D root (main.tscn),
## where Control anchoring can't resolve a fill-screen rect — see
## `scripts/ui/menu_background.gd` for the menu equivalent, which is Control
## based and works because menu scenes are Control-rooted.
##
## Picks a random texture from BACKGROUNDS on _ready() (once per match load)
## and scales it to exactly cover `canvas_size`, keeping the menu's
## background_0 reserved for menus only.

## Backdrop pool randomly picked from for each match.
const BACKGROUNDS: Array[String] = [
	"res://art/ui/backgrounds/background_1.png",
	"res://art/ui/backgrounds/background_2.png",
]

## Fight canvas dimensions (matches main.gd's fixed 1280x720 stage).
@export var canvas_size := Vector2(1280, 720)


func _ready() -> void:
	centered = true
	position = canvas_size * 0.5
	_pick_random_background()


func _pick_random_background() -> void:
	if BACKGROUNDS.is_empty():
		return
	var path: String = BACKGROUNDS[randi() % BACKGROUNDS.size()]
	var tex: Texture2D = load(path)
	texture = tex
	if tex != null:
		var tex_size: Vector2 = tex.get_size()
		scale = canvas_size / tex_size
