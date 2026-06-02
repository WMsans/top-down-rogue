extends GdUnitTestSuite

const _DecorDef = preload("res://src/core/decor_def.gd")

func test_decor_def_defaults() -> void:
	var d := _DecorDef.new()
	assert_that(d.texture).is_null()
	assert_that(d.weight).is_equal(1.0)
	assert_that(d.emits_light).is_true()
	assert_that(d.light_energy).is_equal(1.0)
	assert_that(d.light_radius).is_equal(56.0)
	assert_that(d.flicker_amplitude).is_equal(0.08)
	assert_that(d.light_color).is_equal(Color(0.5, 0.9, 1.0, 1.0))

func test_decor_def_is_resource() -> void:
	var d := _DecorDef.new()
	assert_that(d is Resource).is_true()
