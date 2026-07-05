class_name AttackSlashVfx
extends Node2D

const SLASH_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const SLASH_COLOR_FADE := Color(1.0, 1.0, 1.0, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 6
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func play(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		rotation = direction.angle()
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 12
	p.lifetime = 0.18
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 6
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(1.0, 0.0, 0.0)
	m.spread = 30.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 90.0
	m.initial_velocity_max = 160.0
	m.scale_min = 0.8
	m.scale_max = 1.5
	m.color = SLASH_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(SLASH_COLOR, SLASH_COLOR_FADE)
	return m
