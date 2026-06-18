class_name DragonFangWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.AUTO_FLURRY
	flurry_step_time = 0.14
	light_moves = [_thrust(), _thrust(), _thrust()]
