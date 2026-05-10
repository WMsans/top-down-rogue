extends GdUnitTestSuite

func test_hardness_values() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hardness(registry.MAT_AIR)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_GAS)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_LAVA)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_WATER)).is_equal(0.0)
	assert_that(registry.get_hardness(registry.MAT_DIRT)).is_equal(0.5)
	assert_that(registry.get_hardness(registry.MAT_WOOD)).is_equal(2.0)
	assert_that(registry.get_hardness(registry.MAT_COAL)).is_equal(3.0)
	assert_that(registry.get_hardness(registry.MAT_ICE)).is_equal(4.0)
	assert_that(registry.get_hardness(registry.MAT_STONE)).is_equal(5.0)

func test_hardness_unknown_material() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hardness(-1)).is_equal(0.0)
	assert_that(registry.get_hardness(999)).is_equal(0.0)

func test_carve_scale_formula() -> void:
	assert_float(clampf(5.0 / (5.0 + 0.5), 0.1, 1.0)).is_equal(0.90909).within(0.01)
	assert_float(clampf(5.0 / (5.0 + 2.0), 0.1, 1.0)).is_equal(0.71428).within(0.01)
	assert_float(clampf(5.0 / (5.0 + 5.0), 0.1, 1.0)).is_equal(0.5).within(0.01)
	assert_float(clampf(1.0 / (1.0 + 5.0), 0.1, 1.0)).is_equal(0.16666).within(0.01)
	assert_float(clampf(0.1 / (0.1 + 5.0), 0.1, 1.0)).is_equal(0.01960).within(0.01)
	assert_float(clampf(maxf(0.0, 0.1) / (maxf(0.0, 0.1) + 5.0), 0.1, 1.0)).is_equal(0.1).within(0.01)
	assert_float(clampf(100.0 / (100.0 + 0.5), 0.1, 1.0)).is_equal(0.99502).within(0.01)
