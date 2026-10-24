extends GdUnitTestSuite

# Caves ForestDef content, per the plan's content table. `base_inset()` in
# ForestPropDef reads `texture.get_image()` at runtime to anchor the trunk
# base; that silently returns 0 for a non-CPU-readable (VRAM-compressed)
# import, so every prop texture must expose a readable image.
func test_caves_forest_content() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_that(biome).is_not_null()
	assert_that(biome.forest).is_not_null()

	var trees: Array[ForestPropDef] = biome.forest.tree_defs
	assert_that(trees.is_empty()).is_false()
	var roles := {}
	var families := {}
	for def in trees:
		assert_that(def.texture).is_not_null()
		var img: Image = def.texture.get_image()
		assert_that(img).is_not_null()
		assert_that(img.get_width() > 0 and img.get_height() > 0).is_true()
		roles[def.role] = true
		families[def.family] = true
	assert_that(roles.has("bright")).is_true()
	assert_that(roles.has("dark")).is_true()
	assert_that(roles.has("odd")).is_true()
	assert_that(families.size() >= 2).is_true()

	var rocks: Array[ForestPropDef] = biome.forest.rock_defs
	assert_that(rocks.is_empty()).is_false()
	for def in rocks:
		assert_that(def.texture).is_not_null()
		var img: Image = def.texture.get_image()
		assert_that(img).is_not_null()
		assert_that(img.get_width() > 0 and img.get_height() > 0).is_true()

	var flora: Array[DecorDef] = biome.forest.root_flora
	assert_that(flora.is_empty()).is_false()
	for def in flora:
		assert_that(def.texture).is_not_null()
		assert_that(def.emits_light).is_true()
