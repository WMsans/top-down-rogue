extends GdUnitTestSuite

const NavField = preload("res://src/core/nav/nav_field.gd")

# 32x32 cells per chunk at 8px cells. value 1 = solid.
func _tile(solid_cells: Array) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	for c: Vector2i in solid_cells:
		t[c.y * 32 + c.x] = 1
	return t

func test_grid_tile_marks_world_solid() -> void:
	var nav = NavField.new()
	nav.grid.set_tile(Vector2i(0, 0), _tile([Vector2i(0, 0)]))
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_true()

func test_open_when_no_tile() -> void:
	var nav = NavField.new()
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()

func test_update_does_not_crash_with_no_tiles() -> void:
	var nav = NavField.new()
	nav.update(Vector2(0, 0), 0.0)
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()
