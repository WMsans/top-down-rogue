class_name AimedBurstWeapon
extends RangedWeapon

func _configure() -> void:
	burst_count = 3
	burst_interval = 0.12
	reaim_each_shot = true
	projectile_count = 1
	spread_angle = 0.0
	damage = 4.0