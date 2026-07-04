extends GdUnitTestSuite


func test_default_melee_enemy_builds_bare_weapon() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_object(e.weapon).is_not_null()
	assert_float(e._attack_range).is_equal(28.0)


func test_melee_enemy_with_weapon_resource_uses_it() -> void:
	var res := MeleeWeapon.new()
	res.weapon_reach = 40.0
	res.cooldown = 1.2
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	e.weapon_resource = res
	add_child(e)
	assert_float(e._attack_range).is_equal(40.0)
	assert_float(e.cooldown_duration).is_equal(1.2)


func test_weaponless_melee_enemy_has_no_weapon() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	e.carries_weapon = false
	add_child(e)
	assert_object(e.weapon).is_null()
