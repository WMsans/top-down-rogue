extends GdUnitTestSuite

const RUSTY_SWORD := preload("res://resources/weapons/rusty_sword.tres")
const BONE_DAGGER := preload("res://resources/weapons/bone_dagger.tres")
const THROWING_KNIFE := preload("res://resources/weapons/throwing_knife.tres")
const BOSS_STAFF := preload("res://resources/weapons/boss_staff.tres")

func test_rusty_sword_weapon_reach() -> void:
	assert_that(RUSTY_SWORD.weapon_reach).is_equal(28.0)
	assert_that(RUSTY_SWORD.damage).is_equal(3.0)

func test_bone_dagger_reach() -> void:
	assert_that(BONE_DAGGER.weapon_reach).is_equal(20.0)
	assert_that(BONE_DAGGER.cooldown).is_equal(0.25)

func test_throwing_knife_projectile_speed() -> void:
	assert_that(THROWING_KNIFE.projectile_speed).is_equal(300.0)
	assert_that(THROWING_KNIFE.projectile_count).is_equal(1)

func test_boss_staff_config() -> void:
	assert_that(BOSS_STAFF.damage).is_equal(6.0)
	assert_that(BOSS_STAFF.spread_angle).is_equal(10.0)

func test_weapon_duplication() -> void:
	var original := RUSTY_SWORD
	var copy := original.duplicate()
	copy.damage = 99.0
	assert_that(original.damage).is_equal(3.0)
	assert_that(copy.damage).is_equal(99.0)
