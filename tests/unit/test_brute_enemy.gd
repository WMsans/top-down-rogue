extends GdUnitTestSuite


func _brute() -> BruteEnemy:
	var e: BruteEnemy = auto_free(BruteEnemy.new())
	add_child(e)
	return e


func test_brute_has_boosted_health() -> void:
	var e := _brute()
	assert_int(e.max_health).is_equal(27)
	assert_int(e.health).is_equal(27)


func test_brute_has_reduced_speed() -> void:
	var e := _brute()
	assert_float(e.speed).is_equal_approx(42.0, 0.5)


func test_brute_has_boosted_weapon_damage() -> void:
	var e := _brute()
	assert_float(e.weapon.damage).is_equal_approx(MeleeWeapon.new().damage * 1.3, 0.01)


func test_brute_has_wider_commit_range() -> void:
	var e := _brute()
	assert_float(e._attack_range).is_equal_approx(28.0 * 1.3, 0.1)


func test_brute_has_longer_windup() -> void:
	var e := _brute()
	assert_float(e.windup_duration).is_equal_approx(0.35 * 1.3, 0.01)


func test_brute_wanders_rarely() -> void:
	var e := _brute()
	assert_float(e.wander_pause_time_min).is_greater(2.0)


func test_scene_instantiates_as_brute_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/brute_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is BruteEnemy).is_true()


func test_brute_has_wider_separation_radius() -> void:
	var e := _brute()
	assert_float(e.separation_radius).is_greater(22.0)


func test_brute_has_wider_crowd_spacing() -> void:
	var e := _brute()
	assert_float(e.crowd_spacing_scale).is_greater(1.0)
