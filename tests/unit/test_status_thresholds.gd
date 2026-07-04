extends GdUnitTestSuite


func test_active_thresholds_match_spec() -> void:
	assert_float(StatusRegistry.get_threshold("on_fire")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_threshold("wet")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_threshold("oiled")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_threshold("chilly")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_threshold("frozen")).is_equal_approx(3.0, 0.001)
	assert_float(StatusRegistry.get_threshold("poisoned")).is_equal_approx(0.3, 0.001)
	assert_float(StatusRegistry.get_threshold("bloody")).is_equal_approx(1.0, 0.001)
