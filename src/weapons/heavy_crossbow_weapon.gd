class_name HeavyCrossbowWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 5.0
	cooldown = 1.2
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 280.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	return [PenetrateBehavior.new()]
