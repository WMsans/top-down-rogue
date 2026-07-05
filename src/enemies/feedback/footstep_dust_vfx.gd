class_name FootstepDustVfx
extends Node2D

const FOOTSTEP_INTERVAL: float = 0.28
const DUST_COLOR := Color(0.6, 0.5, 0.4, 0.6)
const DUST_COLOR_FADE := Color(0.6, 0.5, 0.4, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = -1
	z_as_relative = false
	position = Vector2(0.0, 6.0)
	_particles = _build_particles()
	add_child(_particles)


func puff() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 6
	p.lifetime = 0.35
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = -1
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 100.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 8.0
	m.initial_velocity_max = 20.0
	m.scale_min = 0.8
	m.scale_max = 1.4
	m.color = DUST_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(DUST_COLOR, DUST_COLOR_FADE)
	return m
