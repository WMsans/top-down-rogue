extends GdUnitTestSuite

const _MaterialRegistry = preload("res://src/autoload/material_registry.gd")

func test_get_cell_returns_same_instance_for_same_id() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	var a := registry.get_cell(registry.MAT_DIRT)
	var b := registry.get_cell(registry.MAT_DIRT)
	assert_that(a).is_same(b)

func test_get_cell_distinct_per_id() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	var dirt := registry.get_cell(registry.MAT_DIRT)
	var stone := registry.get_cell(registry.MAT_STONE)
	assert_that(dirt).is_not_same(stone)

func test_get_cell_reflects_material_props() -> void:
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	var lava := registry.get_cell(registry.MAT_LAVA)
	assert_that(lava.material_id).is_equal(registry.MAT_LAVA)
	assert_that(lava.is_fluid).is_true()
	assert_int(int(lava.damage)).is_greater(0)
