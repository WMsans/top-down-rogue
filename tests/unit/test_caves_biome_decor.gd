extends GdUnitTestSuite

func test_caves_biome_has_forest_with_glowing_root_flora() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_that(biome).is_not_null()
	assert_that(biome.forest).is_not_null()
	var flora: Array[DecorDef] = biome.forest.root_flora
	assert_that(flora.is_empty()).is_false()
	for def in flora:
		assert_that(def.texture).is_not_null()
		assert_that(def.emits_light).is_true()
