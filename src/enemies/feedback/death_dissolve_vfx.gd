class_name DeathDissolveVfx
extends Node2D

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 4
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func burst(tint: Color) -> void:
	_particles.modulate = tint
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 18
	p.lifetime = 0.4
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 4
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, 0.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 30.0
	m.initial_velocity_max = 90.0
	m.scale_min = 0.6
	m.scale_max = 1.3
	m.color = Color.WHITE
	m.color_ramp = EnemyVfxShared.fade_gradient(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	return m
