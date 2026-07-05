extends GdUnitTestSuite


func test_soft_dot_texture_is_radial_fill() -> void:
	var tex := EnemyVfxShared.soft_dot_texture(8)
	assert_int(tex.fill).is_equal(GradientTexture2D.FILL_RADIAL)
	assert_int(tex.width).is_equal(8)
	assert_int(tex.height).is_equal(8)


func test_fade_gradient_interpolates_hot_to_fade() -> void:
	var hot := Color(1.0, 0.5, 0.2, 1.0)
	var fade := Color(1.0, 0.5, 0.2, 0.0)
	var tex := EnemyVfxShared.fade_gradient(hot, fade)
	assert_that(tex.gradient.get_color(0)).is_equal(hot)
	assert_that(tex.gradient.get_color(1)).is_equal(fade)
