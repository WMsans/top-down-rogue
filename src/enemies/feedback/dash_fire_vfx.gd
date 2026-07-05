class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 6.0
@export var body_length: float = 34.0
@export var body_width: float = 26.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.85)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)
const CORE_COLOR := Color(1.0, 0.85, 0.4, 0.9)

const BULLET_UNIT_POINTS: Array[Vector2] = [
	Vector2(-0.5, -0.32), Vector2(-0.5, 0.32),
	Vector2(-0.38, 0.46), Vector2(-0.15, 0.5),
	Vector2(0.15, 0.42), Vector2(0.35, 0.22),
	Vector2(0.5, 0.0),
	Vector2(0.35, -0.22), Vector2(0.15, -0.42),
	Vector2(-0.15, -0.5), Vector2(-0.38, -0.46),
]

var _particles: GPUParticles2D = null
var _bullet_outer: Polygon2D = null
var _bullet_inner: Polygon2D = null
var _fade_tween: Tween = null
var _intensity: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_bullet_outer = _build_bullet_polygon(FIRE_COLOR)
	_bullet_outer.name = "BulletOuter"
	add_child(_bullet_outer)
	_bullet_inner = _build_bullet_polygon(CORE_COLOR)
	_bullet_inner.name = "BulletInner"
	add_child(_bullet_inner)
	_particles = _build_particles()
	add_child(_particles)
	set_process(true)
	_apply_visual()


func _process(delta: float) -> void:
	_time += delta
	if _intensity > 0.001:
		_apply_visual()


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_particles.restart()
	_particles.emitting = true
	_animate_intensity(1.0, 0.05)


func stop() -> void:
	_particles.emitting = false
	_animate_intensity(0.0, 0.12)


func _animate_intensity(target: float, duration: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_intensity, _intensity, target, duration)


func _set_intensity(v: float) -> void:
	_intensity = v
	_apply_visual()


func _apply_visual() -> void:
	var flicker := 1.0 + sin(_time * 22.0) * 0.08 + sin(_time * 35.0 + 1.3) * 0.05
	_bullet_outer.polygon = _wobble_points(body_length, body_width, 1.0, 0.0)
	_bullet_inner.polygon = _wobble_points(body_length * 0.65, body_width * 0.55, 1.4, 0.6)
	var oc := FIRE_COLOR
	oc.a = clampf(FIRE_COLOR.a * _intensity * flicker, 0.0, 1.0)
	_bullet_outer.color = oc
	var ic := CORE_COLOR
	ic.a = clampf(CORE_COLOR.a * _intensity * (1.0 + sin(_time * 30.0 + 0.4) * 0.12), 0.0, 1.0)
	_bullet_inner.color = ic


func _wobble_points(length: float, width: float, freq_mult: float, phase_offset: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in BULLET_UNIT_POINTS.size():
		var p := BULLET_UNIT_POINTS[i]
		var phase := i * 0.9 + phase_offset
		var wob := 1.0 + sin(_time * 18.0 * freq_mult + phase) * 0.09 + sin(_time * 27.0 * freq_mult + phase * 1.7) * 0.05
		pts.append(Vector2(p.x * length * (1.0 + (wob - 1.0) * 0.4), p.y * width * wob))
	return pts


func _build_bullet_polygon(color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	poly.polygon = PackedVector2Array(BULLET_UNIT_POINTS)
	return poly


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.2
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(-1.0, 0.0, 0.0)
	m.spread = 16.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 55.0
	m.initial_velocity_max = 100.0
	m.scale_min = 1.2
	m.scale_max = 2.4
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.8
	m.turbulence_noise_scale = 2.5
	m.turbulence_influence_min = 0.3
	m.turbulence_influence_max = 0.6
	m.color = FIRE_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return m
