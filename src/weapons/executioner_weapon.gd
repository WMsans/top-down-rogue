class_name ExecutionerWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.55
	charged_flurry_max = 2
	light_moves = [_slash()]
	charged_moves = [_spin(1.0)]
