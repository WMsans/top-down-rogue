class_name QinggangWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.5
	light_moves = [_slash(1.0), _slash(-1.0)]   # alternating up/down
