class_name BloodBladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.6
	charged_flurry_max = 4
	flurry_step_time = 0.12
	light_moves = [_slash()]
	var lunge := _slash(0.0, 0.5)
	lunge.dash_distance = 36.0
	charged_moves = [lunge]
