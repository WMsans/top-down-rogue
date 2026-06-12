extends GdUnitTestSuite

const SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_pick_ranged_weapon_returns_a_pattern_weapon() -> void:
	var d = SpawnDispatcher.new()
	var seen_aimed := false
	for i in range(200):
		var w = d._pick_ranged_weapon()
		assert_bool(w is RangedWeapon).is_true()
		if w is AimedBurstWeapon:
			seen_aimed = true
	assert_bool(seen_aimed).is_true()
