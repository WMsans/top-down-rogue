extends GdUnitTestSuite

func test_create_hit_spec() -> void:
	var spec := HitSpec.new()
	spec.position = Vector2(10, 20)
	spec.direction = Vector2(1, 0)
	spec.damage = 25.0
	spec.is_kill = false
	spec.source_color = Color.RED
	assert_that(spec.position).is_equal(Vector2(10, 20))
	assert_that(spec.direction).is_equal(Vector2(1, 0))
	assert_that(spec.damage).is_equal(25.0)
	assert_that(spec.is_kill).is_false()
	assert_that(spec.source_color).is_equal(Color.RED)

func test_hit_spec_defaults() -> void:
	var spec := HitSpec.new()
	assert_that(spec.position).is_equal(Vector2.ZERO)
	assert_that(spec.is_kill).is_false()
	assert_that(spec.source_color).is_equal(Color.WHITE)
	assert_that(spec.source_radius).is_equal(8.0)
