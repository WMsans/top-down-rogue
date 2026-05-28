extends GdUnitTestSuite

const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")

func test_spawn_node_parents_and_positions() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	var sprite := Sprite2D.new()
	dispatcher.spawn_node(sprite, Vector2(120, -40))

	assert_that(sprite.get_parent()).is_equal(parent)
	assert_that(sprite.global_position).is_equal(Vector2(120, -40))

func test_spawn_node_with_null_does_nothing() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var parent := Node2D.new()
	add_child(parent)
	dispatcher._spawn_parent = parent

	dispatcher.spawn_node(null, Vector2.ZERO)

	assert_that(parent.get_child_count()).is_equal(0)
