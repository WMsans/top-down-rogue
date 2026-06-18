class_name WillowbladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.5
	tap_threshold = 0.12
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_thrust(true, false, 0.0)]   # guaranteed-crit thrust
