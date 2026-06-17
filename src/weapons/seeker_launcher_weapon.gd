class_name SeekerLauncherWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 4.0
	cooldown = 1.5
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 140.0
	projectile_lifetime = 3.5

func _make_behaviors() -> Array:
	var h := HomingBehavior.new()
	h.turn_rate_rad = PI
	return [h]
