extends GdUnitTestSuite

func test_on_fire_def_values() -> void:
	assert_that(StatusRegistry.has_def("on_fire")).is_true()
	assert_float(StatusRegistry.get_threshold("on_fire")).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_burn_dps("on_fire")).is_equal_approx(4.0, 0.001)

func test_frozen_blocks_movement() -> void:
	assert_that(StatusRegistry.blocks_movement("frozen")).is_true()
	assert_float(StatusRegistry.get_threshold("frozen")).is_equal_approx(3.0, 0.001)

func test_chilly_slows() -> void:
	assert_that(StatusRegistry.blocks_movement("chilly")).is_false()
	assert_float(StatusRegistry.get_slow_multiplier("chilly")).is_equal_approx(0.6, 0.001)

func test_unknown_def_safe_defaults() -> void:
	assert_that(StatusRegistry.has_def("nope")).is_false()
	assert_float(StatusRegistry.get_threshold("nope")).is_equal_approx(1.0, 0.001)

func test_material_mapping() -> void:
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_LAVA)).is_equal("on_fire")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_WATER)).is_equal("wet")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_OIL)).is_equal("oiled")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_BLOOD)).is_equal("bloody")
	assert_that(StatusRegistry.stain_for_material(MaterialRegistry.MAT_STONE)).is_equal("")
