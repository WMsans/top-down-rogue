class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 16.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.9)
const FIRE_COLOR_HOT := Color(1.0, 0.85, 0.3, 1.0)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)

var _particles: CPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func start(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		var dir := direction.normalized()
		rotation = dir.angle()
		position = dir * offset_distance
	_particles.restart()
	_particles.emitting = true


func stop() -> void:
	_particles.emitting = false


func _build_particles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.local_coords = true
	p.amount = 24
	p.lifetime = 0.25
	p.direction = Vector2(1.0, 0.0)
	p.spread = 18.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 110.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = FIRE_COLOR
	p.color_ramp = _build_gradient()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, FIRE_COLOR_HOT)
	g.set_color(1, FIRE_COLOR_FADE)
	return g
