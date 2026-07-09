class_name ArmoredEnemy
extends MeleeEnemy

const HP_MULT: float = 1.4
const SPEED_MULT: float = 0.85
const WINDUP_MULT: float = 1.3
const KNOCKBACK_RESIST_MULT: float = 0.25


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	windup_duration *= WINDUP_MULT
	wander_enabled = false
	separation_radius = 22.0 * 1.3
	crowd_spacing_scale = 1.3


func apply_knockback(direction: Vector2, strength: float) -> void:
	super.apply_knockback(direction, strength * KNOCKBACK_RESIST_MULT)
