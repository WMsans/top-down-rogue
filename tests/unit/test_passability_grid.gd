extends GdUnitTestSuite

const PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")

# Build a 256x256 material region (1 byte/pixel) that is all `air` except a
# square block of `solid` in the top-left local area [x0,x1) x [y0,y1).
func _region_with_block(air: int, solid: int, x0: int, y0: int, x1: int, y1: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(256 * 256)
	bytes.fill(air)
	for y in range(y0, y1):
		for x in range(x0, x1):
			bytes[y * 256 + x] = solid
	return bytes

# solid_lut: index = material id, value 1 means "has collider".
func _lut(solid_ids: Array) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(8)
	lut.fill(0)
	for id in solid_ids:
		lut[id] = 1
	return lut

func test_open_when_no_tiles() -> void:
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	assert_bool(g.is_solid_world(Vector2(4, 4))).is_false()

func test_classifies_solid_block() -> void:
	# air id 0, solid id 2. Block covers pixels [0,16) x [0,16) of chunk (0,0).
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(0, 0), _region_with_block(0, 2, 0, 0, 16, 16))
	# A pixel inside the block -> solid cell.
	assert_bool(g.is_solid_world(Vector2(4, 4))).is_true()
	# A pixel well outside the block -> open.
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_false()

func test_any_solid_pixel_marks_whole_cell() -> void:
	# A single solid pixel at (9,9) sits in cell (1,1) (8px cells); that cell is solid.
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(0, 0), _region_with_block(0, 2, 9, 9, 10, 10))
	assert_bool(g.is_solid_world(Vector2(8, 8))).is_true()   # cell (1,1)
	assert_bool(g.is_solid_world(Vector2(0, 0))).is_false()  # cell (0,0)

func test_negative_chunk_coords() -> void:
	var g = PassabilityGrid.new(8, 256, _lut([2]))
	g.update_chunk(Vector2i(-1, -1), _region_with_block(0, 2, 248, 248, 256, 256))
	# World pixel (-4,-4) lives in chunk (-1,-1) local (252,252) -> inside block.
	assert_bool(g.is_solid_world(Vector2(-4, -4))).is_true()

func test_get_tile_returns_set_tile() -> void:
	var g := PassabilityGrid.new(8, 256, PackedByteArray())
	var tile := PackedByteArray()
	tile.resize(32 * 32)
	tile.fill(1)
	g.set_tile(Vector2i(2, -1), tile)
	assert_that(g.get_tile(Vector2i(2, -1))).is_equal(tile)

func test_get_tile_missing_returns_empty() -> void:
	var g := PassabilityGrid.new(8, 256, PackedByteArray())
	assert_that(g.get_tile(Vector2i(9, 9)).is_empty()).is_true()
