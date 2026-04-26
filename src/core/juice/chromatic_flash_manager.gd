extends Node

const CHROMATIC_STRENGTH: float = 0.6
const CHROMATIC_DURATION: float = 0.12

const SCENE := preload("res://scenes/fx/chromatic_flash.tscn")

var _layer: CanvasLayer = null
var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = SCENE.instantiate()
	add_child(_layer)
	_rect = _layer.get_node("Rect")
	_material = _rect.material as ShaderMaterial
	_material.set_shader_parameter("strength", 0.0)


func flash(strength: float = CHROMATIC_STRENGTH, duration: float = CHROMATIC_DURATION) -> void:
	if _material == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_material.set_shader_parameter("strength", strength)
	_tween = create_tween()
	_tween.tween_method(_set_strength, strength, 0.0, duration)


func _set_strength(value: float) -> void:
	if _material:
		_material.set_shader_parameter("strength", value)
