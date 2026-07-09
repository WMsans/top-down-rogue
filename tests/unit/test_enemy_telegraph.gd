extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass


func test_exclaim_label_draws_above_terrain() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	assert_that(e._exclaim_label.z_index).is_equal(10)
	assert_that(e._exclaim_label.z_as_relative).is_false()


func test_show_exclaim_scales_tween_with_windup_duration() -> void:
	var fast: MockEnemy = auto_free(MockEnemy.new())
	fast.windup_duration = 0.2
	var slow: MockEnemy = auto_free(MockEnemy.new())
	slow.windup_duration = 0.6
	assert_that(fast._telegraph_scale()).is_less(slow._telegraph_scale())
