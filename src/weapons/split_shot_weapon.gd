class_name SplitShotWeapon
extends RangedWeapon

func _configure() -> void:
	burst_count = 2
	burst_interval = 0.18
	reaim_each_shot = true
	projectile_count = 2
	spread_angle = 30.0
	damage = 4.0