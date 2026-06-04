extends GdUnitTestSuite

const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")

# Type-specific tuning still lives in the .tres files.
func test_rusty_sword_type_specific_tres_fields() -> void:
	assert_that(RUSTY_SWORD.weapon_reach).is_equal(28.0)

func test_bone_dagger_type_specific_tres_fields() -> void:
	assert_that(BONE_DAGGER.weapon_reach).is_equal(20.0)

func test_throwing_knife_type_specific_tres_fields() -> void:
	assert_that(THROWING_KNIFE.projectile_speed).is_equal(180.0)
	assert_that(THROWING_KNIFE.projectile_count).is_equal(1)

# Universal fields now come from weapons.csv via the registry.
func test_rusty_sword_universal_fields_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.name).is_equal("Rusty Sword")

func test_bone_dagger_cooldown_from_registry() -> void:
	var w = WeaponRegistry.get_weapon_by_id("bone_dagger")
	assert_that(w.cooldown).is_equal(0.25)

func test_boss_staff_universal_and_type_specific() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.spread_angle).is_equal(10.0)

func test_weapon_duplication_independent() -> void:
	var original = WeaponRegistry.get_weapon_by_id("rusty_sword")
	var copy = original.duplicate()
	copy.damage = 99.0
	assert_that(original.damage).is_equal(3.0)
	assert_that(copy.damage).is_equal(99.0)
