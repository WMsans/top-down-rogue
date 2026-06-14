extends GdUnitTestSuite


func test_base_enemy_does_not_move_during_attack() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_bool(e._moves_during_attack()).is_false()
