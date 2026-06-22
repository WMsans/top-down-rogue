extends GdUnitTestSuite

const _BiomeDef = preload("res://src/core/biome_def.gd")


func test_biome_def_default_gold_multiplier() -> void:
	var b: BiomeDef = _BiomeDef.new()
	assert_float(b.gold_multiplier).is_equal_approx(1.0, 0.0001)


func test_magma_biome_gold_multiplier() -> void:
	var b: BiomeDef = load("res://assets/biomes/magma.tres")
	assert_float(b.gold_multiplier).is_equal_approx(0.9, 0.0001)


func test_vault_biome_gold_multiplier() -> void:
	var b: BiomeDef = load("res://assets/biomes/vault.tres")
	assert_float(b.gold_multiplier).is_equal_approx(1.2, 0.0001)
