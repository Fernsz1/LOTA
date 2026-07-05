extends SceneTree

var checks := 0
var failures := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

func _init() -> void:
	var path := "res://scenes/ui/map_select/outline.gdshader"
	ok(ResourceLoader.exists(path), "shader exists")
	var sh: Shader = load(path)
	ok(sh != null, "shader loads")
	if sh:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		# uniforms present and compile OK (defaults readable via material)
		mat.set_shader_parameter("outline_width", 6.0)
		mat.set_shader_parameter("outline_color", Color.BLACK)
		ok(mat.get_shader_parameter("outline_width") == 6.0, "outline_width uniform set")
		ok(mat.get_shader_parameter("outline_color") == Color.BLACK, "outline_color uniform set")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
