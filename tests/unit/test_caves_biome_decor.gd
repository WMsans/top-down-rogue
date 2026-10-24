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


const DB32 := ["000000", "222034", "45283c", "663931", "8f563b", "df7126", "d9a066", "eec39a", "fbf236", "99e550", "6abe30", "37946e", "4b692f", "524b24", "323c39", "3f3f74", "306082", "5b6ee1", "639bff", "5fcde4", "cbdbfc", "ffffff", "9badb7", "847e87", "696a6a", "595652", "76428a", "ac3232", "d95763", "d77bba", "8f974a", "8a6f30"]


# Trimmed to Colour1 round trees + pines and two rocks, all in DawnBringer 32.
func test_caves_forest_trimmed_and_db32() -> void:
	var forest: ForestDef = (load("res://assets/biomes/caves.tres") as BiomeDef).forest
	assert_int(forest.tree_defs.size()).is_equal(5)
	assert_int(forest.rock_defs.size()).is_equal(2)
	assert_int(forest.secondary_groups).is_equal(1)
	assert_int(forest.rock_attempts).is_equal(1)
	var families := {}
	for def in forest.tree_defs:
		assert_str(def.texture.resource_path).contains("/Trees/Colour1/")
		families[def.family] = true
	assert_array(families.keys()).contains_exactly_in_any_order(["round", "pine"])
	var defs: Array = []
	defs.append_array(forest.tree_defs)
	defs.append_array(forest.rock_defs)
	for def in defs:
		var img: Image = def.texture.get_image()
		img.decompress()
		var off_palette := ""
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.0 and not DB32.has(c.to_html(false)):
					off_palette = "%s (%d,%d) %s" % [def.texture.resource_path, x, y, c.to_html(false)]
					break
			if off_palette != "":
				break
		assert_str(off_palette).is_empty()
