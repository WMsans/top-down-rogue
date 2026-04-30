extends GdUnitTestSuite

func test_is_emitter_true_for_lava() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_LAVA)).is_true()

func test_is_emitter_false_for_air() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_AIR)).is_false()

func test_is_emitter_false_for_water() -> void:
	assert_that(MaterialRegistry.is_emitter(MaterialRegistry.MAT_WATER)).is_false()

func test_is_emitter_false_for_invalid_id() -> void:
	assert_that(MaterialRegistry.is_emitter(-1)).is_false()
	assert_that(MaterialRegistry.is_emitter(99999)).is_false()
