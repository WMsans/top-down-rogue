class_name TwinDaggersWeapon
extends AdvancedMeleeWeapon

func _init() -> void:
	super._init()
	weapon_reach = 22.0
	arc_angle = deg_to_rad(60.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.AUTO_FLURRY
	flurry_step_time = 0.05
	light_moves = [_slash(), _slash()]
	charged_moves = []
