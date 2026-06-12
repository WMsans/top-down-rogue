class_name FanWeapon
extends RangedWeapon

func _configure() -> void:
	burst_count = 1
	burst_interval = 0.12
	reaim_each_shot = false
	projectile_count = 3
	spread_angle = 40.0
	damage = 4.0