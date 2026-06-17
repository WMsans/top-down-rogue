class_name BerserkerAxeWeapon
extends MeleeWeapon

const MAX_RAMP := 1.6

func _init() -> void:
	super._init()
	weapon_reach = 34.0
	arc_angle = deg_to_rad(110.0)

func _native_modify_hit_damage(user: Node, _target: Node, dmg: float) -> float:
	var frac: float = 1.0
	if user != null:
		var inv = user.get_node_or_null("PlayerInventory")
		if inv != null and inv.has_method("get_health_fraction"):
			frac = inv.get_health_fraction()
	return dmg * lerpf(1.0, MAX_RAMP, 1.0 - clampf(frac, 0.0, 1.0))
