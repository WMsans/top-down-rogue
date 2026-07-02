extends GdUnitTestSuite

const CASES := {
	"willowblade": "res://src/weapons/willowblade_weapon.gd",
	"executioner": "res://src/weapons/executioner_weapon.gd",
	"void_sword": "res://src/weapons/void_sword_weapon.gd",
	"quake_hammer": "res://src/weapons/quake_hammer_weapon.gd",
	"blood_blade": "res://src/weapons/blood_blade_weapon.gd",
	"arc_railgun": "res://src/weapons/arc_railgun_weapon.gd",
}


func _charged_total(w) -> float:
	if w is AdvancedMeleeWeapon:
		w._ensure_moves()
		var per: float = 0.0
		for m in w.charged_moves:
			per += m.damage_mult
		if w.charged_flurry_max > 1:
			return per * float(w.charged_flurry_max)
		return per
	elif w is ChargedRangedWeapon:
		return w.charge_damage_mult
	return 1.0


func _tap(w) -> float:
	if w is AdvancedMeleeWeapon:
		if not w.light_moves.is_empty():
			return w.light_moves[0].damage_mult
		return 1.0
	elif w is ChargedRangedWeapon:
		return 1.0
	return 1.0


func test_charged_release_is_1_8_to_2_5x_tap() -> void:
	for id in CASES:
		var w = load(CASES[id]).new()
		var ratio: float = _charged_total(w) / _tap(w)
		assert_float(ratio) \
			.override_failure_message("%s charged ratio %.2f outside [1.8, 2.5]" % [id, ratio]) \
			.is_between(1.8, 2.5)
