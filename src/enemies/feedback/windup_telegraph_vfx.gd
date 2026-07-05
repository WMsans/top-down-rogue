class_name WindupTelegraphVfx
extends Node2D

const GLOW_COLOR := Color(1.0, 0.9, 0.3, 0.8)
const GLOW_COLOR_FADE := Color(1.0, 0.9, 0.3, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 5
	z_as_relative = false
	position = Vector2(0.0, -6.0)
	_particles = _build_particles()
	add_child(_particles)


func play() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 8
	p.lifetime = 0.3
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 5
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 20.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 10.0
	m.initial_velocity_max = 24.0
	m.scale_min = 0.5
	m.scale_max = 1.0
	m.color = GLOW_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(GLOW_COLOR, GLOW_COLOR_FADE)
	return m
