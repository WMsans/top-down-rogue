extends GdUnitTestSuite 

func test_query_empty_grid_returns_default_cell() -> void:
	var tp := TerrainPhysical.new()
	var cell := tp.query(Vector2(50, 60))
	assert_that(cell.material_id).is_equal(0)
	assert_that(cell.is_solid).is_false()
	assert_that(cell.damage).is_equal(0.0)

func test_query_cached_cell() -> void:
	var tp := TerrainPhysical.new()
	tp._grid[Vector2i(10, 20)] = MaterialRegistry.MAT_WOOD
	var cell := tp.query(Vector2(10, 20))
	assert_that(cell.material_id).is_equal(MaterialRegistry.MAT_WOOD)

func test_invalidate_removes_from_cache() -> void:
	var tp := TerrainPhysical.new()
	tp._grid[Vector2i(15, 25)] = MaterialRegistry.MAT_STONE
	tp.invalidate_rect(Rect2i(10, 20, 10, 10))
	var cell := tp.query(Vector2(15, 25))
	assert_that(cell.material_id).is_equal(0)

func test_set_center_updates_grid_center() -> void:
	var tp := TerrainPhysical.new()
	tp.set_center(Vector2i(500, 500))
	assert_that(tp._grid_center).is_equal(Vector2i(500, 500))
