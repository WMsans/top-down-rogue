class_name QuakeHammerWeapon
extends AdvancedMeleeWeapon

const SHOCKWAVE_RADIUS := 70.0
const SHOCKWAVE_STRENGTH := 140.0

func _init() -> void:
	super._init()
	weapon_reach = 32.0
	arc_angle = deg_to_rad(110.0)

func _setup_moves() -> void:
	combo_mode = ComboMode.TAP_CHAIN
	charge_time_full = 0.8
	charged_flurry_max = 1
	light_moves = [_slash()]
	charged_moves = [_slash(0.0, 2.0)]   # heavy slam hit; shockwave added below

func _do_charged_attack(user: Node, ratio: float) -> void:
	super._do_charged_attack(user, ratio)
	_emit_shockwave(user)

func _emit_shockwave(user) -> void:
	CombatUtil.radial_knockback(user, SHOCKWAVE_RADIUS, SHOCKWAVE_STRENGTH)
