class_name SniperWeapon
extends RangedWeapon

func _configure() -> void:
	burst_count = 1
	reaim_each_shot = false
	projectile_count = 1
	spread_angle = 0.0
	damage = 20.0
	cooldown = 2.5
	projectile_speed = 260.0


func _make_behaviors() -> Array:
	var pen := SniperPenetrationBehavior.new()
	pen.pierces = 2
	return [pen]