extends GdUnitTestSuite


func _armored() -> ArmoredEnemy:
	var e: ArmoredEnemy = auto_free(ArmoredEnemy.new())
	add_child(e)
	return e


func test_armored_has_boosted_health() -> void:
	var e := _armored()
	assert_int(e.max_health).is_equal(21)


func test_armored_has_reduced_speed() -> void:
	var e := _armored()
	assert_float(e.speed).is_equal_approx(51.0, 0.5)


func test_armored_does_not_wander() -> void:
	var e := _armored()
	assert_bool(e.wander_enabled).is_false()


func test_armored_has_longer_windup() -> void:
	var e := _armored()
	assert_float(e.windup_duration).is_equal_approx(0.35 * 1.3, 0.01)


func test_armored_resists_knockback() -> void:
	var e := _armored()
	e.is_elite = false
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(25.0, 0.5)


func test_armored_elite_stacks_knockback_resistance() -> void:
	var e: ArmoredEnemy = auto_free(ArmoredEnemy.new())
	e.is_elite = true
	add_child(e)
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(10.0, 0.5)


func test_scene_instantiates_as_armored_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/armored_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is ArmoredEnemy).is_true()


func test_armored_has_wider_separation_radius() -> void:
	var e := _armored()
	assert_float(e.separation_radius).is_greater(22.0)


func test_armored_has_wider_crowd_spacing() -> void:
	var e := _armored()
	assert_float(e.crowd_spacing_scale).is_greater(1.0)
