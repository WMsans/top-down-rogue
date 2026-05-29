extends GdUnitTestSuite

func test_dust_is_registered() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_DUST).is_greater(0)

func test_dust_is_fluid_no_collider() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_fluid(registry.MAT_DUST)).is_true()
	assert_bool(registry.has_collider(registry.MAT_DUST)).is_false()

func test_dust_is_inert() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_flammable(registry.MAT_DUST)).is_false()
	assert_that(registry.get_hardness(registry.MAT_DUST)).is_equal(0.0)
	assert_that(registry.get_damage(registry.MAT_DUST)).is_equal(0)

func test_dust_in_get_fluids() -> void:
	var registry := MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.get_fluids().has(registry.MAT_DUST)).is_true()