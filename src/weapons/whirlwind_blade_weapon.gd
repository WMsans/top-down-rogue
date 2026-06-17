class_name WhirlwindBladeWeapon
extends MeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 30.0
	arc_angle = deg_to_rad(90.0)
