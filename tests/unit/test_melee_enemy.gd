extends GdUnitTestSuite


func test_melee_enemy_has_speed_with_weapon_resource() -> void:
	var e := MeleeEnemy.new()
	e.weapon_resource = MeleeWeapon.new()
	e.weapon_resource.weapon_reach = 32.0
	e.weapon_resource.cooldown = 0.5
	e._ready()
	assert_that(e.speed).is_greater(0.0)
