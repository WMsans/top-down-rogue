class_name WarScytheWeapon
extends MeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 44.0
	arc_angle = deg_to_rad(300.0)
	half_arc = deg_to_rad(150.0)
