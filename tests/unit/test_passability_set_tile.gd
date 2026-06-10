extends GdUnitTestSuite

const PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# 32x32 cells per 256px chunk at 8px cells. value 1 = solid.
func _tile(solid_cells: Array) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	for c: Vector2i in solid_cells:
		t[c.y * 32 + c.x] = 1
	return t

func test_set_tile_marks_cell_solid() -> void:
	var g = PassabilityGrid.new(8, 256, PackedByteArray())
	g.set_tile(Vector2i(0, 0), _tile([Vector2i(1, 1)]))
	assert_bool(g.is_solid_world(Vector2(8, 8))).is_true()    # cell (1,1)
	assert_bool(g.is_solid_world(Vector2(0, 0))).is_false()   # cell (0,0)

func test_set_tile_negative_chunk() -> void:
	var g = PassabilityGrid.new(8, 256, PackedByteArray())
	# chunk (-1,-1) local cell (31,31) -> world px (-8,-8)
	g.set_tile(Vector2i(-1, -1), _tile([Vector2i(31, 31)]))
	assert_bool(g.is_solid_world(Vector2(-8, -8))).is_true()
