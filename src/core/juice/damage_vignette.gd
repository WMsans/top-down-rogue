class_name DamageVignette
extends CanvasLayer

const DAMAGE_PULSE_STRENGTH := 0.5
const DAMAGE_PULSE_UP := 0.07
const DAMAGE_PULSE_DOWN := 0.18
const LOW_HEALTH_STRENGTH := 0.18
const LOW_HEALTH_RATIO := 0.25
const LOW_HEALTH_PULSE_SPEED := 1.2
const LOW_HEALTH_TRANSITION := 0.4

const EMBER_COLOR := Color(1.0, 0.4, 0.05, 1.0)
const EMBER_MAX_STRENGTH := 0.5
const EMBER_SMOOTH := 6.0

var _shader_material: ShaderMaterial
var _color_rect: ColorRect
var _current_baseline: float = 0.0
var _is_low_health: bool = false
var _pulse_tween: Tween
var _ember_material: ShaderMaterial
var _ember_target: float = 0.0

@onready var _viewport := get_viewport()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_color_rect = ColorRect.new()
	_color_rect.anchor_right = 1.0
	_color_rect.anchor_bottom = 1.0
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_color_rect)

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = preload("res://shaders/ui/damage_vignette.gdshader")
	_shader_material.set_shader_parameter("intensity", 0.0)
	_color_rect.material = _shader_material

	call_deferred("_connect_to_player")

	var ember_rect := ColorRect.new()
	ember_rect.anchor_right = 1.0
	ember_rect.anchor_bottom = 1.0
	ember_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ember_rect)

	_ember_material = ShaderMaterial.new()
	_ember_material.shader = preload("res://shaders/ui/damage_vignette.gdshader")
	_ember_material.set_shader_parameter("intensity", 0.0)
	_ember_material.set_shader_parameter("vignette_color", EMBER_COLOR)
	ember_rect.material = _ember_material


func pulse(damage: float) -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(_set_intensity, _get_intensity(), DAMAGE_PULSE_STRENGTH, DAMAGE_PULSE_UP)
	_pulse_tween.tween_method(_set_intensity, DAMAGE_PULSE_STRENGTH, _current_baseline, DAMAGE_PULSE_DOWN)


func _get_intensity() -> float:
	return _shader_material.get_shader_parameter("intensity")


func _set_intensity(value: float) -> void:
	_shader_material.set_shader_parameter("intensity", value)


func _connect_to_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		get_tree().create_timer(0.1).timeout.connect(_connect_to_player)
		return
	var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
	if inventory == null:
		get_tree().create_timer(0.1).timeout.connect(_connect_to_player)
		return
	inventory.health_changed.connect(_on_health_changed)


func set_burn_intensity(t: float) -> void:
	_ember_target = clampf(t, 0.0, 1.0) * EMBER_MAX_STRENGTH


func get_ember_intensity() -> float:
	return _ember_material.get_shader_parameter("intensity") if _ember_material else 0.0


func _on_health_changed(current: int, maximum: int) -> void:
	if current <= 0 or maximum <= 0:
		_is_low_health = false
		_current_baseline = 0.0
		return
	var ratio := float(current) / float(maximum)
	if ratio <= LOW_HEALTH_RATIO and not _is_low_health:
		_is_low_health = true
		_current_baseline = LOW_HEALTH_STRENGTH
		_interpolate_to_baseline(LOW_HEALTH_TRANSITION)
	elif ratio > LOW_HEALTH_RATIO and _is_low_health:
		_is_low_health = false
		_current_baseline = 0.0
		_interpolate_to_baseline(0.3)
	elif ratio <= LOW_HEALTH_RATIO and _is_low_health:
		pass


func _interpolate_to_baseline(duration: float) -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(_set_intensity, _get_intensity(), _current_baseline, duration)


func _process(_delta: float) -> void:
	if _ember_material:
		var cur: float = _ember_material.get_shader_parameter("intensity")
		var step := clampf(_delta * EMBER_SMOOTH, 0.0, 1.0)
		_ember_material.set_shader_parameter("intensity", lerpf(cur, _ember_target, step))

	if not _is_low_health:
		return
	if _pulse_tween and _pulse_tween.is_valid():
		return
	var oscillation := _current_baseline * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.001 * LOW_HEALTH_PULSE_SPEED * TAU))
	_shader_material.set_shader_parameter("intensity", oscillation)
