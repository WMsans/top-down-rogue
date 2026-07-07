extends GdUnitTestSuite

const _MaterialRegistry = preload("res://src/autoload/material_registry.gd")

func test_hazard_bits() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hazard_bit(registry.MAT_LAVA)).is_equal(0)
	assert_that(registry.get_hazard_bit(registry.MAT_EXPLODE_WAVE)).is_equal(1)
	assert_that(registry.get_hazard_bit(registry.MAT_OIL)).is_equal(2)
	assert_that(registry.get_hazard_bit(registry.MAT_BLOOD)).is_equal(3)

func test_non_hazard_returns_minus_one() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hazard_bit(registry.MAT_AIR)).is_equal(-1)
	assert_that(registry.get_hazard_bit(registry.MAT_DIRT)).is_equal(-1)
	assert_that(registry.get_hazard_bit(registry.MAT_STONE)).is_equal(-1)
	assert_that(registry.get_hazard_bit(-1)).is_equal(-1)
	assert_that(registry.get_hazard_bit(999)).is_equal(-1)

func test_hazard_mask_constants() -> void:
	assert_that(MaterialRegistry.HAZARD_LAVA).is_equal(1)
	assert_that(MaterialRegistry.HAZARD_FIRE).is_equal(2)
	assert_that(MaterialRegistry.HAZARD_OIL).is_equal(4)
	assert_that(MaterialRegistry.HAZARD_BLOOD).is_equal(8)
