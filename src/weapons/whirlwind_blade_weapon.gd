class_name WhirlwindBladeWeapon
extends AdvancedMeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 30.0
	arc_angle = deg_to_rad(90.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.6
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_spin()]
