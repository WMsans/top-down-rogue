extends GdUnitTestSuite

func test_caves_has_treasure_room_with_chest_and_sign() -> void:
	var biome: BiomeDef = load("res://assets/biomes/caves.tres")
	assert_object(biome).is_not_null()
	var found := false
	for tmpl in biome.room_templates:
		var rt := tmpl as RoomTemplate
		if rt.composition == null:
			continue
		var comp := rt.composition as ArenaComposition
		if comp.arena_kind != &"reward":
			continue
		var has_chest := false
		var has_sign := false
		for f in comp.features:
			if f is FeatureChestSpawn:
				has_chest = true
			if f is FeatureRoomSign:
				has_sign = true
		if has_chest and has_sign:
			found = true
	assert_bool(found).is_true()
