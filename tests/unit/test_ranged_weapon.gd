extends GdUnitTestSuite

func test_ranged_weapon_configuration() -> void:
	var w := RangedWeapon.new()
	w.projectile_count = 1
	w.projectile_speed = 100.0
	w.damage = 5.0
	assert_that(w.damage).is_equal(5.0)
	assert_that(w.projectile_count).is_equal(1)
	assert_that(w.cooldown).is_greater(0.0)

func test_ranged_weapon_spread() -> void:
	var w := RangedWeapon.new()
	w.projectile_count = 3
	w.spread_angle = 30.0
	assert_that(w.spread_angle).is_equal(30.0)
	assert_that(w.projectile_count).is_equal(3)
