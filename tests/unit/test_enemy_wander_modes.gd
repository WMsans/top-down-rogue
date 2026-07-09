extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_wander_disabled_holds_still() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.wander_enabled = false
	e._wander_timer = 0.0
	e._wander_is_paused = true
	e._process_idle(0.1)
	assert_vector(e.velocity).is_equal(Vector2.ZERO)


func test_wander_default_matches_original_timing_bounds() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	assert_float(e.wander_move_time_min).is_equal(1.0)
	assert_float(e.wander_move_time_max).is_equal(3.0)
	assert_float(e.wander_pause_time_min).is_equal(0.5)
	assert_float(e.wander_pause_time_max).is_equal(1.5)
	assert_float(e.wander_speed_mult).is_equal(0.5)


func test_custom_wander_speed_mult_applied_while_moving() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.speed = 100.0
	e.wander_speed_mult = 1.0
	e._wander_is_paused = false
	e._wander_direction = Vector2.RIGHT
	e._wander_timer = 5.0
	e._process_idle(0.016)
	assert_float(e.velocity.x).is_equal_approx(100.0, 0.5)
