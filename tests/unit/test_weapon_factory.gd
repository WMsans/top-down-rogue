extends GdUnitTestSuite

func test_factory_builds_existing_melee_from_row() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w).is_not_null()
	assert_that(w is MeleeWeapon).is_true()
	assert_that(w.weapon_reach).is_equal(28.0)
	assert_that(w.arc_angle).is_equal_approx(deg_to_rad(90.0), 0.001)
	assert_that(w.damage).is_equal(3.0)

func test_factory_builds_bespoke_archetype() -> void:
	var w = WeaponRegistry.get_weapon_by_id("void_sword")
	assert_that(w).is_not_null()
	assert_str(w.get_script().resource_path).contains("void_sword_weapon.gd")

func test_factory_builds_new_data_weapon() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rapier")
	assert_that(w).is_not_null()
	assert_that(w is MeleeWeapon).is_true()
	assert_that(w.crit_chance).is_equal(0.3)

func test_factory_skips_unregistered_archetype() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("not_a_real_weapon_id")).is_null()

func test_factory_builds_twin_daggers_archetype() -> void:
	var w = WeaponRegistry.get_weapon_by_id("twin_daggers")
	assert_that(w).is_not_null()
	assert_str(w.get_script().resource_path).contains("twin_daggers_weapon.gd")

func test_ranged_tuning_from_csv() -> void:
	var w = WeaponRegistry.get_weapon_by_id("spread_shot")
	assert_that(w.projectile_count).is_equal(3)
	assert_that(w.spread_angle).is_equal(30.0)
