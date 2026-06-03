extends GdUnitTestSuite

const BIOME_PATHS := [
	"res://assets/biomes/caves.tres",
	"res://assets/biomes/mines.tres",
	"res://assets/biomes/magma.tres",
	"res://assets/biomes/frozen.tres",
	"res://assets/biomes/vault.tres",
]

func test_every_biome_has_a_non_rotatable_size96_shop() -> void:
	for path in BIOME_PATHS:
		var biome: BiomeDef = load(path)
		assert_that(biome).is_not_null()
		var found := false
		for t in biome.room_templates:
			var rt := t as RoomTemplate
			if rt != null and rt.png_path.ends_with("shop_a.png"):
				found = true
				assert_that(rt.size_class).is_equal(96)
				assert_that(rt.rotatable).is_false()
				assert_that(rt.weight).is_greater(2.0)
		assert_that(found).override_failure_message("no shop template in %s" % path).is_true()
