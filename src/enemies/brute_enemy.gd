class_name BruteEnemy
extends MeleeEnemy

const HP_MULT: float = 1.8
const SPEED_MULT: float = 0.7
const DAMAGE_MULT: float = 1.3
const COMMIT_RANGE_MULT: float = 1.3
const WINDUP_MULT: float = 1.3


func _ready() -> void:
	super._ready()
	max_health = int(float(max_health) * HP_MULT)
	health = max_health
	speed = _speed_base * SPEED_MULT
	_speed_base = speed
	if weapon:
		weapon.damage *= DAMAGE_MULT
	_attack_range *= COMMIT_RANGE_MULT
	windup_duration *= WINDUP_MULT
	wander_move_time_min = 0.3
	wander_move_time_max = 0.8
	wander_pause_time_min = 3.0
	wander_pause_time_max = 6.0
