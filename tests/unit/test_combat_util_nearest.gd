extends GdUnitTestSuite

func _enemy(at: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	n.add_to_group("attackable")
	add_child(n)
	n.global_position = at
	return n

func test_returns_nearest_within_range_sorted() -> void:
	var near := _enemy(Vector2(10, 0))
	var far := _enemy(Vector2(50, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [], 2, 100.0)
	assert_int(out.size()).is_equal(2)
	assert_object(out[0]).is_same(near)
	assert_object(out[1]).is_same(far)

func test_excludes_listed_nodes() -> void:
	var a := _enemy(Vector2(10, 0))
	var b := _enemy(Vector2(20, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [a], 5, 100.0)
	assert_int(out.size()).is_equal(1)
	assert_object(out[0]).is_same(b)

func test_drops_targets_out_of_range() -> void:
	_enemy(Vector2(500, 0))
	var out := CombatUtil.nearest_attackables(get_tree(), Vector2.ZERO, [], 5, 100.0)
	assert_int(out.size()).is_equal(0)
