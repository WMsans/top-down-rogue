extends GdUnitTestSuite

const _AR = preload("res://src/core/arena_region.gd")
const ArenaFeature = preload("res://src/core/arena_feature.gd")
const ArenaComposition = preload("res://src/core/arena_composition.gd")
const FeatureBossSpawn = preload("res://src/core/features/feature_boss_spawn.gd")

func test_composition_defaults() -> void:
	var c = ArenaComposition.new()
	assert_that(c.arena_kind).is_equal(&"boss")
	assert_that(c.features.size()).is_equal(0)

func test_composition_holds_features() -> void:
	var c = ArenaComposition.new()
	var f := FeatureBossSpawn.new()
	c.features.append(f)
	assert_that(c.features.size()).is_equal(1)
