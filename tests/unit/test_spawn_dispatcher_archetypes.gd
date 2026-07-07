extends GdUnitTestSuite


func test_weighted_pick_respects_zero_weight_exclusion() -> void:
	var weights := {"a": 1.0, "b": 0.0}
	for i in range(20):
		assert_str(SpawnDispatcher._weighted_pick(weights)).is_equal("a")


func test_weighted_pick_only_returns_known_keys() -> void:
	var weights := {"grunt": 40.0, "brute": 15.0, "skirmisher": 20.0, "armored": 15.0, "cultist": 10.0}
	for i in range(50):
		assert_bool(weights.has(SpawnDispatcher._weighted_pick(weights))).is_true()


func test_pick_pooled_weapon_returns_valid_melee_weapon() -> void:
	var dispatcher := SpawnDispatcher.new()
	var w := dispatcher._pick_pooled_weapon("grunt", true, 1, 0)
	assert_object(w).is_not_null()


func test_pick_pooled_weapon_returns_valid_ranged_weapon() -> void:
	var dispatcher := SpawnDispatcher.new()
	var w := dispatcher._pick_pooled_weapon("archer", false, 1, 0)
	assert_object(w).is_not_null()
