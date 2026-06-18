extends GdUnitTestSuite

const Dispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_gauntlet_extra_count_is_zero_near_origin() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(0)).is_equal(0)
	assert_int(Dispatcher.gauntlet_extra_count(2)).is_equal(0)

func test_gauntlet_extra_count_grows_with_distance() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(3)).is_equal(1)
	assert_int(Dispatcher.gauntlet_extra_count(6)).is_equal(2)

func test_gauntlet_extra_count_is_capped() -> void:
	assert_int(Dispatcher.gauntlet_extra_count(100)).is_less_equal(4)
