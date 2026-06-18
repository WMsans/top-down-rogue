class_name FlameLobberWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 3.0
	cooldown = 1.5
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 110.0
	projectile_lifetime = 0.6

func _make_behaviors() -> Array:
	var s := SplatBehavior.new()
	s.material = "lava"
	s.radius = 6.0
	return [s]
