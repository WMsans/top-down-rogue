class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 6.0
@export var body_length: float = 34.0
@export var body_width: float = 26.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.85)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)
const FLAME_FILL_COUNT := 50

const BULLET_UNIT_POINTS: Array[Vector2] = [
	Vector2(-0.5, -0.32), Vector2(-0.5, 0.32),
	Vector2(-0.38, 0.46), Vector2(-0.15, 0.5),
	Vector2(0.15, 0.42), Vector2(0.35, 0.22),
	Vector2(0.5, 0.0),
	Vector2(0.35, -0.22), Vector2(0.15, -0.42),
	Vector2(-0.15, -0.5), Vector2(-0.38, -0.46),
]

var _tail: GPUParticles2D = null
var _flame_fill: CPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_flame_fill = _build_flame_fill()
	add_child(_flame_fill)
	_tail = _build_tail()
	add_child(_tail)


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_flame_fill.restart()
	_flame_fill.emitting = true
	_tail.restart()
	_tail.emitting = true


func stop() -> void:
	_flame_fill.emitting = false
	_tail.emitting = false


func _build_flame_fill() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "FlameFill"
	p.emitting = false
	p.amount = FLAME_FILL_COUNT
	p.lifetime = 0.15
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.z_as_relative = false
	p.z_index = 6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _sample_bullet_points(FLAME_FILL_COUNT)
	p.direction = Vector2.RIGHT
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.damping_min = 6.0
	p.damping_max = 10.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _build_pop_curve()
	p.hue_variation_min = -0.05
	p.hue_variation_max = 0.05
	p.color_ramp = _build_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return p


func _build_pop_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


func _build_gradient(hot: Color, fade: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, hot)
	g.set_color(1, fade)
	return g


func _sample_bullet_points(count: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var attempts := 0
	var max_attempts := count * 50
	while pts.size() < count and attempts < max_attempts:
		attempts += 1
		var candidate := Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
		if _point_in_bullet_polygon(candidate):
			pts.append(Vector2(candidate.x * body_length, candidate.y * body_width))
	return pts


func _point_in_bullet_polygon(pt: Vector2) -> bool:
	var inside := false
	var n := BULLET_UNIT_POINTS.size()
	var j := n - 1
	for i in n:
		var pi: Vector2 = BULLET_UNIT_POINTS[i]
		var pj: Vector2 = BULLET_UNIT_POINTS[j]
		if (pi.y > pt.y) != (pj.y > pt.y):
			var x_intersect := (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x
			if pt.x < x_intersect:
				inside = not inside
		j = i
	return inside


func _build_tail() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.amount = 14
	p.lifetime = 0.2
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_tail_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_tail_process_material() -> ParticleProcessMaterial:
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
