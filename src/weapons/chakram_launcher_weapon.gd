class_name ChakramLauncherWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.5
	cooldown = 1.2
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 160.0
	projectile_lifetime = 2.0

func _make_behaviors() -> Array:
	var r := ReturnBehavior.new()
	r.out_time = 0.5
	return [r]
