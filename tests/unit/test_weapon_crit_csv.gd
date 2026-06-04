extends GdUnitTestSuite

func test_caliburn_high_crit_no_status() -> void:
	var w = WeaponRegistry.get_weapon_by_id("caliburn")
	assert_that(w).is_not_null()
	assert_float(w.crit_chance).is_equal_approx(0.35, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")

func test_flame_sword_crit_on_fire() -> void:
	var w = WeaponRegistry.get_weapon_by_id("flame_sword")
	assert_float(w.crit_chance).is_equal_approx(0.15, 0.001)
	assert_that(w.crit_status).is_equal("on_fire")

func test_frost_sword_crit_chilly() -> void:
	var w = WeaponRegistry.get_weapon_by_id("frost_sword")
	assert_that(w.crit_status).is_equal("chilly")

func test_heavenly_sword_crit_chilly() -> void:
	var w = WeaponRegistry.get_weapon_by_id("heavenly_sword")
	assert_that(w.crit_status).is_equal("chilly")

func test_non_crit_weapon_defaults() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_float(w.crit_chance).is_equal_approx(0.0, 0.001)
	assert_float(w.crit_multiplier).is_equal_approx(2.0, 0.001)
	assert_that(w.crit_status).is_equal("")
