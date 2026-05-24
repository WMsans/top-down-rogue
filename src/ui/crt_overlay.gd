extends CanvasLayer

## Full-screen CRT post-process. Sits at the highest CanvasLayer so its
## ColorRect samples everything below via hint_screen_texture in the shader.

const CRT_SHADER := preload("res://shaders/post/crt.gdshader")

func _ready() -> void:
	layer = 128
	follow_viewport_enabled = true
	var rect := ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CRT_SHADER
	rect.material = mat
	add_child(rect)
