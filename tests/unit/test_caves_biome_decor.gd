extends GdUnitTestSuite

func test_caves_biome_has_three_glowing_flora() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_that(biome).is_not_null()
	assert_that(biome.decor_defs.size()).is_equal(3)
	for def in biome.decor_defs:
		assert_that(def.texture).is_not_null()
		assert_that(def.emits_light).is_true()
	assert_that(biome.decor_chance > 0.0).is_true()
