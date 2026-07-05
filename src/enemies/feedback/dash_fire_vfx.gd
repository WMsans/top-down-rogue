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


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_bullet_outer = _build_bullet_polygon(body_length, body_width, FIRE_COLOR)
	_bullet_outer.name = "BulletOuter"
	add_child(_bullet_outer)
	_bullet_inner = _build_bullet_polygon(body_length * 0.65, body_width * 0.55, CORE_COLOR)
	_bullet_inner.name = "BulletInner"
	add_child(_bullet_inner)
	_particles = _build_particles()
	add_child(_particles)
	_set_bullet_alpha(0.0)


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_particles.restart()
	_particles.emitting = true
	_animate_bullet_alpha(1.0, 0.05)


func stop() -> void:
	_particles.emitting = false
	_animate_bullet_alpha(0.0, 0.12)


func _animate_bullet_alpha(target: float, duration: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(_bullet_outer, "color:a", target * FIRE_COLOR.a, duration)
	_fade_tween.tween_property(_bullet_inner, "color:a", target * CORE_COLOR.a, duration)


func _set_bullet_alpha(a: float) -> void:
	var oc := _bullet_outer.color
	oc.a = a
	_bullet_outer.color = oc
	var ic := _bullet_inner.color
	ic.a = a
	_bullet_inner.color = ic


func _build_bullet_polygon(length: float, width: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	var pts := PackedVector2Array()
	for p in BULLET_UNIT_POINTS:
		pts.append(Vector2(p.x * length, p.y * width))
	poly.polygon = pts
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
	m.spread = 14.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 40.0
	m.initial_velocity_max = 80.0
	m.scale_min = 1.0
	m.scale_max = 2.0
	m.color = FIRE_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return m
