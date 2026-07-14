extends GdUnitTestSuite

const MineScene := preload("res://scenes/props/mine.tscn")


func test_mine_arms_after_delay() -> void:
	var mine : Mine = auto_free(MineScene.instantiate())
	get_tree().root.add_child(mine)
	mine.arm(0.2)
	assert_bool(mine.is_armed()).is_false()
	await get_tree().create_timer(0.25).timeout
	assert_bool(mine.is_armed()).is_true()


func test_mine_explodes_on_timeout_and_frees() -> void:
	var mine : Mine = auto_free(MineScene.instantiate())
	mine.timeout = 0.2
	mine._skip_arm_for_test()
	get_tree().root.add_child(mine)
	mine.begin_timeout()
	await get_tree().create_timer(0.3).timeout
	assert_bool(is_instance_valid(mine)).is_false()