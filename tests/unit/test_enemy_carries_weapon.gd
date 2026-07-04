extends GdUnitTestSuite


func test_carries_weapon_defaults_true() -> void:
	var e: Enemy = auto_free(Enemy.new())
	add_child(e)
	assert_bool(e.carries_weapon).is_true()
