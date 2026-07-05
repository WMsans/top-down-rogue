class_name DashFireVfx
extends Node2D

@export var offset_distance: float = 16.0

const FIRE_COLOR := Color(1.0, 0.55, 0.15, 0.9)
const FIRE_COLOR_FADE := Color(1.0, 0.2, 0.05, 0.0)

var _particles: GPUParticles2D = null


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


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.25
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(1.0, 0.0, 0.0)
	m.spread = 18.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 110.0
	m.scale_min = 1.5
	m.scale_max = 3.0
	m.color = FIRE_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(FIRE_COLOR, FIRE_COLOR_FADE)
	return m
