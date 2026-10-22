extends GdUnitTestSuite

const BerserkerAxe = preload("res://src/weapons/berserker_axe_weapon.gd")

func test_axe_reach_and_arc() -> void:
	var w: BerserkerAxeWeapon = BerserkerAxe.new()
	assert_float(w.weapon_reach).is_equal_approx(34.0, 0.01)
	assert_float(rad_to_deg(w.arc_angle)).is_equal_approx(110.0, 0.5)
