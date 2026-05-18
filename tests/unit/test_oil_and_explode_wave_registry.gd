extends GdUnitTestSuite

const _MaterialRegistry = preload("res://src/autoload/material_registry.gd")

func test_mat_oil_registered() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_OIL).is_greater(0)
	assert_that(registry.is_flammable(registry.MAT_OIL)).is_true()
	assert_that(registry.get_ignition_temp(registry.MAT_OIL)).is_equal(200)
	assert_that(registry.is_fluid(registry.MAT_OIL)).is_true()
	assert_that(registry.has_collider(registry.MAT_OIL)).is_false()
	assert_that(registry.has_wall_extension(registry.MAT_OIL)).is_false()

func test_mat_oil_burn_health() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	var oil_def = registry.materials[registry.MAT_OIL]
	assert_that(oil_def.burn_health).is_equal(60)

func test_mat_explode_wave_registered() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_EXPLODE_WAVE).is_greater(0)
	assert_that(registry.is_flammable(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.is_fluid(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.has_collider(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.has_wall_extension(registry.MAT_EXPLODE_WAVE)).is_false()
	assert_that(registry.get_glow(registry.MAT_EXPLODE_WAVE)).is_greater_equal(10.0)
