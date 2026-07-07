extends GdUnitTestSuite

const _MaterialRegistry = preload("res://src/autoload/material_registry.gd")

func test_bedrock_exists_with_collider() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_BEDROCK).is_greater(0)
	assert_bool(registry.has_collider(registry.MAT_BEDROCK)).is_true()
	assert_bool(registry.has_wall_extension(registry.MAT_BEDROCK)).is_true()

func test_bedrock_is_inert() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_bool(registry.is_flammable(registry.MAT_BEDROCK)).is_false()
	assert_bool(registry.is_fluid(registry.MAT_BEDROCK)).is_false()
	assert_that(registry.get_damage(registry.MAT_BEDROCK)).is_equal(0)

func test_bedrock_registered_after_dust() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.MAT_DUST).is_equal(12)
	assert_that(registry.MAT_BEDROCK).is_equal(13)
