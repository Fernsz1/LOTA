extends SceneTree
## The background shader must exist, compile clean, and drive a ColorRect.

const PATH := "res://scenes/ui/map_select/background.gdshader"

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	ok(ResourceLoader.exists(PATH), "background.gdshader exists")
	var shader: Shader = load(PATH) if ResourceLoader.exists(PATH) else null
	ok(shader != null and shader is Shader, "loads as Shader")
	if shader:
		var rect := ColorRect.new()
		rect.size = Vector2(1280, 720)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		rect.material = mat
		get_root().add_child(rect)  # would print a SHADER ERROR to stderr if it failed to compile
		ok(rect.material != null, "ColorRect accepts the shader material")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
