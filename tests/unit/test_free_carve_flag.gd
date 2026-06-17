extends GdUnitTestSuite

func test_default_carve_strength_is_damage() -> void:
	var w := MeleeWeapon.new()
	w.damage = 5.0
	assert_float(w._solid_carve_strength(5.0)).is_equal_approx(5.0, 0.001)

func test_free_carve_uses_overwhelming_strength() -> void:
	var w := MeleeWeapon.new()
	w.free_carve = true
	assert_float(w._solid_carve_strength(5.0)).is_equal(MeleeWeapon.FREE_CARVE_STRENGTH)

func test_free_carve_survives_duplicate() -> void:
	var w := MeleeWeapon.new()
	w.free_carve = true
	var copy: MeleeWeapon = w.duplicate(true)
	assert_bool(copy.free_carve).is_true()
