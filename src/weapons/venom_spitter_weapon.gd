class_name VenomSpitterWeapon
extends RangedWeapon

func _configure() -> void:
	damage = 2.5
	cooldown = 1.3
	projectile_count = 1
	spread_angle = 0.0
	projectile_speed = 120.0
	projectile_lifetime = 0.6

func _make_behaviors() -> Array:
	var s := SplatBehavior.new()
	s.material = "gas"
	s.radius = 6.0
	s.gas_density = 200
	return [s]
