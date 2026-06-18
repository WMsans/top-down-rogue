extends GdUnitTestSuite

const FlowField = preload("res://src/core/nav/flow_field.gd")

# Minimal grid stub matching the interface FlowField needs: is_solid_cell(cell).
class StubGrid:
	var solids: Dictionary = {}  # Vector2i -> true
	func set_solid(cell: Vector2i) -> void:
		solids[cell] = true
	func is_solid_cell(cell: Vector2i) -> bool:
		return solids.has(cell)

func _run_to_completion(field, grid) -> void:
	while field.is_building():
		field.step(grid)

func _dirs_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true

func test_center_has_no_flow() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# Player cell -> zero flow (already at target).
	assert_vector(f.sample_direction(Vector2(0, 0))).is_equal(Vector2.ZERO)

func test_adjacent_points_toward_player() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# Cell (1,0) is one cell right of the player; flow should push back toward -x.
	var dir := f.sample_direction(Vector2(8, 0))  # world pos in cell (1,0)
	assert_float(dir.x).is_less(0.0)

func test_routes_around_wall() -> void:
	# Vertical wall at x=2 for y in [-6..2], open gap at y in [3..6].
	var grid := StubGrid.new()
	for y in range(-6, 3):
		grid.set_solid(Vector2i(2, y))
	var f = FlowField.new(8, 6, 100000, 8, 999.0)
	f.begin_build(Vector2i(0, 0))
	_run_to_completion(f, grid)
	# The wall cell itself has no flow.
	assert_vector(f.sample_direction(Vector2(2 * 8, 0))).is_equal(Vector2.ZERO)
	# A cell on the far side of the wall is still reachable (routed around the gap).
	var far := f.sample_direction(Vector2(4 * 8, 0))  # cell (4,0)
	assert_bool(far != Vector2.ZERO).is_true()

func test_incremental_equals_one_shot() -> void:
	var grid := StubGrid.new()
	for y in range(-6, 3):
		grid.set_solid(Vector2i(2, y))
	# Tiny budget -> many steps.
	var f_inc = FlowField.new(8, 6, 5, 8, 999.0)
	f_inc.begin_build(Vector2i(0, 0))
	_run_to_completion(f_inc, grid)
	# Huge budget -> one step.
	var f_one = FlowField.new(8, 6, 100000, 8, 999.0)
	f_one.begin_build(Vector2i(0, 0))
	f_one.step(grid)
	assert_bool(f_one.is_building()).is_false()
	assert_bool(_dirs_equal(f_inc.live_dir(), f_one.live_dir())).is_true()

func test_idle_skip_and_rebuild_on_move() -> void:
	var grid := StubGrid.new()
	var f = FlowField.new(8, 6, 100000, 8, 3.0)
	f.update(grid, Vector2(0, 0), 0.0)          # first build (origin cell 0,0)
	assert_bool(f.is_building()).is_false()
	assert_bool(f.has_live()).is_true()
	f.update(grid, Vector2(0, 0), 0.1)          # stationary, fresh -> no rebuild
	assert_vector(f.live_origin_cell()).is_equal(Vector2i(0, 0))
	f.update(grid, Vector2(8 * 9, 0), 0.0)      # moved 9 cells (>=8) -> rebuild
	assert_vector(f.live_origin_cell()).is_equal(Vector2i(9, 0))
