class_name PhantomBladeWeapon
extends AdvancedMeleeWeapon

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	combo_reset_time = 0.5
	light_moves = [_slash(1.0), _thrust(false, true, 0.0)]   # up-slash, ghost thrust
