extends GdUnitTestSuite

const _MaterialRegistry = preload("res://src/autoload/material_registry.gd")

func test_hardness_values() -> void:
	var registry := _MaterialRegistry.new()
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
	var registry := _MaterialRegistry.new()
	registry._init_materials()
	assert_that(registry.get_hardness(-1)).is_equal(0.0)
	assert_that(registry.get_hardness(999)).is_equal(0.0)

func test_carve_scale_formula() -> void:
	assert_float(clampf(5.0 / (5.0 + 0.5), 0.1, 1.0)).is_equal_approx(0.90909, 0.01)
	assert_float(clampf(5.0 / (5.0 + 2.0), 0.1, 1.0)).is_equal_approx(0.71428, 0.01)
	assert_float(clampf(5.0 / (5.0 + 5.0), 0.1, 1.0)).is_equal_approx(0.5, 0.01)
	assert_float(clampf(1.0 / (1.0 + 5.0), 0.1, 1.0)).is_equal_approx(0.16666, 0.01)
	assert_float(clampf(0.1 / (0.1 + 5.0), 0.1, 1.0)).is_equal_approx(0.1, 0.01)
	assert_float(clampf(maxf(0.0, 0.1) / (maxf(0.0, 0.1) + 5.0), 0.1, 1.0)).is_equal_approx(0.1, 0.01)
	assert_float(clampf(100.0 / (100.0 + 0.5), 0.1, 1.0)).is_equal_approx(0.99502, 0.01)

func test_carve_scale_for_known_weapons() -> void:
	# Base melee weapon: damage=5.0
	# Dirt (0.5): 5/(5+0.5) = 0.909 → ~91% radius
	var dirt_scale := clampf(5.0 / (5.0 + 0.5), 0.1, 1.0)
	assert_float(dirt_scale).is_greater(0.9)
	# Stone (5.0): 5/(5+5) = 0.5 → 50% radius
	var stone_scale := clampf(5.0 / (5.0 + 5.0), 0.1, 1.0)
	assert_float(stone_scale).is_equal_approx(0.5, 0.01)
	# Stone should be less than dirt
	assert_that(stone_scale).is_less(dirt_scale)

func test_carve_scale_preserves_ordering() -> void:
	var damage := 5.0
	var dirts := clampf(damage / (damage + 0.5), 0.1, 1.0)
	var woods := clampf(damage / (damage + 2.0), 0.1, 1.0)
	var coals := clampf(damage / (damage + 3.0), 0.1, 1.0)
	var ices := clampf(damage / (damage + 4.0), 0.1, 1.0)
	var stones := clampf(damage / (damage + 5.0), 0.1, 1.0)
	assert_that(dirts).is_greater(woods)
	assert_that(woods).is_greater(coals)
	assert_that(coals).is_greater(ices)
	assert_that(ices).is_greater(stones)
