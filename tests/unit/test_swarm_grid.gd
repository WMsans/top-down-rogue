extends GdUnitTestSuite

const SwarmGridScript = preload("res://src/core/swarm_grid.gd")

func _node_at(parent: Node, pos: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	parent.add_child(n)
	n.global_position = pos
	return n

func test_neighbors_includes_nearby_node() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	var b := _node_at(self, Vector2(20, 0))
	grid.rebuild([a, b])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(b)).is_true()

func test_neighbors_excludes_far_node() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	var far := _node_at(self, Vector2(500, 500))
	grid.rebuild([a, far])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(far)).is_false()

func test_query_spans_three_by_three_cells() -> void:
	# cell_size 32: a node one cell away (diagonally) is still a neighbor.
	var grid = SwarmGridScript.new(32.0)
	var center := _node_at(self, Vector2(0, 0))
	var diag := _node_at(self, Vector2(40, 40))  # cell (1,1) relative to (0,0)
	grid.rebuild([center, diag])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_bool(near.has(diag)).is_true()

func test_rebuild_clears_previous_contents() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := _node_at(self, Vector2(0, 0))
	grid.rebuild([a])
	grid.rebuild([])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_int(near.size()).is_equal(0)

func test_rebuild_skips_freed_nodes() -> void:
	var grid = SwarmGridScript.new(32.0)
	var a := Node2D.new()
	add_child(a)
	a.global_position = Vector2(0, 0)
	a.free()
	grid.rebuild([a])
	var near := grid.query_neighbors(Vector2(0, 0))
	assert_int(near.size()).is_equal(0)
