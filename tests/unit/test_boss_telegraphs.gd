extends GdUnitTestSuite

const BossTelegraph = preload("res://src/enemies/fx/boss_telegraph.gd")


func test_ground_crack_line_returns_node2d() -> void:
	var parent : Node2D = auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var node : Node2D = BossTelegraph.ground_crack_line(parent, Vector2.ZERO, Vector2(40, 0), 0.3)
	assert_that(node is Node2D).is_true()
	assert_that(node.get_parent()).is_equal(parent)
	assert_bool(is_instance_valid(node)).is_true()
	await get_tree().create_timer(0.4).timeout
	assert_bool(is_instance_valid(node)).is_false()


func test_expanding_circle_is_node2d_and_frees() -> void:
	var parent : Node2D = auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var node : Node2D = BossTelegraph.expanding_circle(parent, Vector2.ZERO, 60.0, 0.3)
	assert_that(node is Node2D).is_true()
	await get_tree().create_timer(0.4).timeout
	assert_bool(is_instance_valid(node)).is_false()


func test_column_rise_converging_shockwave_all_free_after_duration() -> void:
	var parent : Node2D = auto_free(Node2D.new())
	get_tree().root.add_child(parent)
	var a : Node2D = BossTelegraph.column_rise(parent, Vector2.ZERO, 40.0, 0.3)
	var b : Node2D = BossTelegraph.shockwave_ring(parent, Vector2.ZERO, 50.0, 0.3)
	var c : Node2D = BossTelegraph.converging_particles(parent, Vector2.ZERO, 40.0, 0.3, Color.YELLOW)
	await get_tree().create_timer(0.45).timeout
	var nodes : Array = [a, b, c]
	for node in nodes:
		assert_bool(is_instance_valid(node)).is_false()