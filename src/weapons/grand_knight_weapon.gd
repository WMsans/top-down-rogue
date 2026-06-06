class_name GrandKnightWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.6
	light_moves = [_slash(), _slash(), _thrust()]
