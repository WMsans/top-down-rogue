extends GdUnitTestSuite


func test_pick_pooled_weapon_archer_returns_valid_weapon() -> void:
	var d := SpawnDispatcher.new()
	for i in range(20):
		var w := d._pick_pooled_weapon("archer", false, 1, 0)
		assert_object(w).is_not_null()
