extends GdUnitTestSuite

func test_rusty_sword_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.weapon_reach).is_equal(28.0)

func test_bone_dagger_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("bone_dagger")
	assert_that(w.weapon_reach).is_equal(20.0)

func test_throwing_knife_type_specific_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("throwing_knife")
	assert_that(w.projectile_speed).is_equal(180.0)
	assert_that(w.projectile_count).is_equal(1)

func test_rusty_sword_universal_fields_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.name).is_equal("Rusty Sword")

func test_bone_dagger_cooldown_from_registry() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("bone_dagger").cooldown).is_equal(0.25)

func test_boss_staff_universal_and_type_specific() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.spread_angle).is_equal(10.0)

func test_weapon_duplication_independent() -> void:
	var original = WeaponRegistry.get_weapon_by_id("rusty_sword")
	var copy = original.duplicate(true)
	copy.damage = 99.0
	assert_that(original.damage).is_equal(3.0)
	assert_that(copy.damage).is_equal(99.0)
