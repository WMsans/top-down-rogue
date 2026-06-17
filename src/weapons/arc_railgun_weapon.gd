class_name ArcRailgunWeapon
extends ChargedRangedWeapon

func _configure() -> void:
	damage = 8.0
	cooldown = 1.6
	charge_time_full = 0.7
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 320.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	return [PenetrateBehavior.new()]
