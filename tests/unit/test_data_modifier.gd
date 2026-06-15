extends GdUnitTestSuite

func test_base_modifier_new_hooks_are_noops() -> void:
	var m: Modifier = Modifier.new()
	assert_that(m.modify_stat("damage", 5.0)).is_equal(5.0)
	assert_that(m.modify_hit_damage(null, null, null, 7.0)).is_equal(7.0)
	m.on_hit_target(null, null, null)
	m.on_kill(null, null, null)

func test_weapon_cooldown_damage_survive_duplicate() -> void:
	var w: Weapon = Weapon.new()
	w.cooldown = 0.42
	w.damage = 9.0
	var copy: Weapon = w.duplicate(true)
	assert_that(copy.cooldown).is_equal(0.42)
	assert_that(copy.damage).is_equal(9.0)
