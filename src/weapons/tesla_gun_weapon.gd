class_name TeslaGunWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.0
	cooldown = 1.1
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 220.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	var c := ChainBehavior.new()
	c.jumps = 3
	c.range_px = 160.0
	return [c]
