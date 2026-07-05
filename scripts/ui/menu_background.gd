extends Control
## Procedural sunset-island backdrop shared by the menu screens (main menu,
## stage select, character select). Painted art can be assigned to `art`
## directly: it fills ArtSlot above the procedural layers (which auto-hide)
## while the vignette stays on top.
##
## Always shows the same fixed backdrop (background_0) — menus intentionally
## don't randomize. For the randomized in-match arena backdrop, see
## `scripts/match/arena_background.gd`, which is a plain Sprite2D (this
## script's Control-based anchoring only resolves under a Control/CanvasLayer
## parent, which the Node2D-rooted fight scene isn't).

const PROCEDURAL_LAYERS: Array[String] = [
	"Sky", "Sea", "SunGlow", "SunCore", "Islands", "PalmLeft", "PalmRight",
]

## Fixed backdrop used by all menu screens.
const MENU_BACKGROUND := "res://art/ui/backgrounds/background_0.png"

@export var art: Texture2D = null: set = _set_art
@export_range(0.0, 1.0) var glow_strength := 1.0: set = _set_glow_strength
@export var animate := true

@onready var _sun_glow: TextureRect = $SunGlow
@onready var _sun_core: TextureRect = $SunCore
@onready var _art_slot: TextureRect = $ArtSlot


func _ready() -> void:
	if art == null:
		art = load(MENU_BACKGROUND)
	_apply_art()
	_apply_glow()
	if animate:
		_start_animation()


func _set_art(value: Texture2D) -> void:
	art = value
	if is_inside_tree():
		_apply_art()


func _set_glow_strength(value: float) -> void:
	glow_strength = clampf(value, 0.0, 1.0)
	if is_inside_tree():
		_apply_glow()


func _apply_art() -> void:
	_art_slot.texture = art
	for layer: String in PROCEDURAL_LAYERS:
		get_node(NodePath(layer)).visible = art == null


func _apply_glow() -> void:
	_sun_glow.modulate.a = glow_strength
	_sun_core.modulate.a = glow_strength


func _start_animation() -> void:
	var glow_tween := create_tween().set_loops()
	glow_tween.tween_property(_sun_glow, "modulate:a", glow_strength * 0.7, 3.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow_tween.tween_property(_sun_glow, "modulate:a", glow_strength, 3.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var left_tween := create_tween().set_loops()
	left_tween.tween_property($PalmLeft, "rotation_degrees", 1.1, 4.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	left_tween.tween_property($PalmLeft, "rotation_degrees", -0.6, 4.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var right_tween := create_tween().set_loops()
	right_tween.tween_property($PalmRight, "rotation_degrees", -1.0, 5.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	right_tween.tween_property($PalmRight, "rotation_degrees", 0.7, 5.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
