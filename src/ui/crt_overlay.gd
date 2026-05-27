extends CanvasLayer

## Full-screen CRT post-process. Sits at the highest CanvasLayer so its
## ColorRect samples everything below via hint_screen_texture in the shader.

const CRT_SHADER := preload("res://shaders/post/crt.gdshader")

@export var scanline_intensity: float = 0.25
@export var scanline_period_rows: float = 3.0
@export var scanline_dark_rows: float = 1.0
@export var scanline_speed: float = 12.0
@export var curvature: float = 0.08
@export var vignette_strength: float = 0.35
@export var vignette_softness: float = 0.45
@export var pixel_rows: float = 180.0

var _material: ShaderMaterial

func _ready() -> void:
	layer = 128
	follow_viewport_enabled = true
	var rect := ColorRect.new()
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = CRT_SHADER
	_apply_params()
	rect.material = _material
	add_child(rect)


func _apply_params() -> void:
	_material.set_shader_parameter("scanline_intensity", scanline_intensity)
	_material.set_shader_parameter("scanline_period_rows", scanline_period_rows)
	_material.set_shader_parameter("scanline_dark_rows", scanline_dark_rows)
	_material.set_shader_parameter("scanline_speed", scanline_speed)
	_material.set_shader_parameter("curvature", curvature)
	_material.set_shader_parameter("vignette_strength", vignette_strength)
	_material.set_shader_parameter("vignette_softness", vignette_softness)
	_material.set_shader_parameter("pixel_rows", pixel_rows)
