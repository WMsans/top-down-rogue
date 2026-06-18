extends GdUnitTestSuite

const _SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

# Same stub shape as test_spawn_validation: read_region answers from a solid set.
class StubWM extends Node:
	var solid_cells: Dictionary = {}   # Vector2i -> true

	func read_region(rect: Rect2i) -> PackedByteArray:
		var air := MaterialRegistry.MAT_AIR
		var solid := (air + 1) % 256
		var data := PackedByteArray()
		data.resize(rect.size.x * rect.size.y)
		for y in range(rect.size.y):
			for x in range(rect.size.x):
				var cell := Vector2i(rect.position.x + x, rect.position.y + y)
				data[y * rect.size.x + x] = solid if solid_cells.has(cell) else air
		return data


func _make_dispatcher(wm) -> Node:
	var d = _SpawnDispatcher.new()
	d._world_manager = wm
	return d


func test_clear_position_returned_unchanged() -> void:
	var wm := StubWM.new()                       # all air
	var d := _make_dispatcher(wm)
	var pos := Vector2(200, 200)
	assert_vector(d._resolve_clear_position(pos)).is_equal(pos)
	d.free()


func test_blocked_marker_nudges_to_nearby_air() -> void:
	var wm := StubWM.new()
	# Wall band to the LEFT of center: x in [center-6 .. center-2] across the
	# vertical span. This intersects the center footprint (x from center-6) but
	# not a footprint shifted +8 on x (x from center+2), leaving open space to
	# the right within one ring.
	for dx in range(-6, -1):
		for dy in range(-10, 11):
			wm.solid_cells[Vector2i(200 + dx, 200 + dy)] = true
	var d := _make_dispatcher(wm)
	var result = d._resolve_clear_position(Vector2(200, 200))
	assert_that(result).is_not_null()
	# The chosen spot must itself be clear and within the search radius.
	assert_bool(SpawnValidation.footprint_clear(wm, result)).is_true()
	assert_float((result as Vector2).distance_to(Vector2(200, 200))) \
		.is_less_equal(float(d.NUDGE_MAX_RINGS * d.NUDGE_CELL) * 1.5)
	d.free()


func test_fully_enclosed_marker_returns_null() -> void:
	var wm := StubWM.new()
	# Solidify everything within the search radius + footprint reach.
	var reach := 6 + (3 * 8) + 2
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			wm.solid_cells[Vector2i(200 + dx, 200 + dy)] = true
	var d := _make_dispatcher(wm)
	assert_that(d._resolve_clear_position(Vector2(200, 200))).is_null()
	d.free()
