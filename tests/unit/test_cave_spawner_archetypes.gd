extends GdUnitTestSuite


func test_cave_spawner_picks_valid_melee_weapon_for_each_archetype() -> void:
	var spawner := CaveSpawner.new()
	for archetype in SpawnDispatcher.MELEE_ARCHETYPE_WEIGHTS.keys():
		var w := spawner._pick_pooled_weapon(archetype, true)
		assert_object(w).is_not_null()


func test_cave_spawner_picks_valid_ranged_weapon_for_each_archetype() -> void:
	var spawner := CaveSpawner.new()
	for archetype in SpawnDispatcher.RANGED_ARCHETYPE_WEIGHTS.keys():
		var w := spawner._pick_pooled_weapon(archetype, false)
		assert_object(w).is_not_null()
