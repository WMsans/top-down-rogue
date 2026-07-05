class_name HurtSparkVfx
extends Node2D

const SPARK_COLOR := Color(1.0, 0.95, 0.85, 1.0)
const SPARK_COLOR_FADE := Color(1.0, 0.3, 0.2, 0.0)

var _particles: GPUParticles2D = null


func _ready() -> void:
	z_index = 7
	z_as_relative = false
	_particles = _build_particles()
	add_child(_particles)


func burst() -> void:
	_particles.restart()
	_particles.emitting = true


func _build_particles() -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = "Particles"
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.2
	p.texture = EnemyVfxShared.soft_dot_texture()
	p.process_material = _build_process_material()
	p.z_as_relative = false
	p.z_index = 7
	return p


func _build_process_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0.0, -1.0, 0.0)
	m.spread = 180.0
	m.gravity = Vector3.ZERO
	m.initial_velocity_min = 60.0
	m.initial_velocity_max = 130.0
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.color = SPARK_COLOR
	m.color_ramp = EnemyVfxShared.fade_gradient(SPARK_COLOR, SPARK_COLOR_FADE)
	return m
