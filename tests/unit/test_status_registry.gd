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


func test_get_icon_alpha_below_threshold_is_zero() -> void:
	assert_float(StatusRegistry.get_icon_alpha("on_fire", 0.5)).is_equal_approx(0.0, 0.001)

func test_get_icon_alpha_at_threshold_is_min() -> void:
	assert_float(StatusRegistry.get_icon_alpha("on_fire", 1.0)).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.001)

func test_get_icon_alpha_saturates_at_one() -> void:
	var stain := 1.0 + StatusRegistry.ICON_ALPHA_RAMP
	assert_float(StatusRegistry.get_icon_alpha("on_fire", stain)).is_equal_approx(1.0, 0.001)
	assert_float(StatusRegistry.get_icon_alpha("on_fire", stain + 10.0)).is_equal_approx(1.0, 0.001)

func test_get_icon_alpha_midpoint_between_min_and_one() -> void:
	var mid := StatusRegistry.get_icon_alpha("on_fire", 1.0 + StatusRegistry.ICON_ALPHA_RAMP * 0.5)
	assert_float(mid).is_greater(StatusRegistry.ICON_MIN_ALPHA)
	assert_float(mid).is_less(1.0)

func test_get_icon_uses_per_status_threshold() -> void:
	# frozen threshold is 3.0; at 3.0 it should read min alpha, not saturated.
	assert_float(StatusRegistry.get_icon_alpha("frozen", 3.0)).is_equal_approx(StatusRegistry.ICON_MIN_ALPHA, 0.001)
	assert_float(StatusRegistry.get_icon_alpha("frozen", 2.0)).is_equal_approx(0.0, 0.001)

func test_get_icon_returns_texture_for_each_status() -> void:
	for id in ["on_fire", "wet", "oiled", "chilly", "frozen", "bloody"]:
		assert_object(StatusRegistry.get_icon(id)).is_not_null()

func test_get_icon_unknown_is_null() -> void:
	assert_object(StatusRegistry.get_icon("nope")).is_null()


func test_status_def_has_mode_and_default_duration() -> void:
	var def := StatusDef.new("test_stain", "Test", Color.WHITE, 1.0, 1.0)
	assert_int(def.mode).is_equal(StatusDef.Mode.STAIN)
	assert_float(def.default_duration).is_equal(0.0)

func test_timed_status_def() -> void:
	var def := StatusDef.new("test_timed", "Timed", Color.BLUE, 0.0, 0.0, StatusDef.Category.HARMFUL, 0.0, false, 1.0, "", StatusDef.Mode.TIMED, 0.5)
	assert_int(def.mode).is_equal(StatusDef.Mode.TIMED)
	assert_float(def.default_duration).is_equal(0.5)
