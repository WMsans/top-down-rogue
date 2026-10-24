extends GdUnitTestSuite

const _COMP_PATH := "res://assets/arenas/guidance/guidance_room_composition.tres"

func test_guidance_room_is_small_and_signless() -> void:
	var comp: ArenaComposition = load(_COMP_PATH)
	assert_int(comp.nominal_radius).is_equal(80)
	assert_int(comp.inner_disc_radius).is_equal(80)
	for f in comp.features:
		assert_bool(f is FeaturePlaqueSet).is_false()
		if f is FeatureFloorOverlay:
			assert_float(f.radius).is_equal(80.0)
		elif f is FeatureWoodWall:
			assert_float(f.inner_radius).is_equal(72.0)
			assert_float(f.outer_radius).is_equal(80.0)
		elif f is FeatureLanternCluster:
			for spec in f.lanterns:
				assert_float(spec.offset.length()).is_less(72.0)
