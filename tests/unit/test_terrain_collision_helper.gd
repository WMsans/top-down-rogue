extends GdUnitTestSuite

const TerrainCollisionHelper := preload("res://src/core/terrain_collision_helper.gd")

class FakeComputeDevice extends RefCounted:
	var dispatched_coords: Array = []
	var pending_readback: Dictionary = {}
	func dispatch_collider_pack(_chunks: Dictionary, coords: Array) -> void:
		dispatched_coords = coords.duplicate()
	func read_collider_buffer_coalesced() -> Dictionary:
		var out := pending_readback.duplicate()
		pending_readback = {}
		return out

class FakeWorldManager extends RefCounted:
	var compute_device
	var chunks: Dictionary = {}
	var dirty_marks: Array = []
	func mark_terrain_dirty(coord: Vector2i) -> void:
		dirty_marks.append(coord)


func _make_helper() -> TerrainCollisionHelper:
	var wm := FakeWorldManager.new()
	wm.compute_device = FakeComputeDevice.new()
	var h := TerrainCollisionHelper.new()
	h.world_manager = wm
	return h


func test_empty_dirty_set_does_nothing() -> void:
	var h := _make_helper()
	h.rebuild_dirty({}, 0.016)
	assert_that(h.world_manager.compute_device.dispatched_coords).is_empty()


func test_mark_dirty_adds_to_set() -> void:
	var h := _make_helper()
	h.mark_dirty(Vector2i(1, 2))
	h.mark_dirty(Vector2i(1, 2))  # duplicate is idempotent
	h.mark_dirty(Vector2i(3, 4))
	assert_that(h._dirty_chunks.size()).is_equal(2)


func test_dispatch_drains_dirty_up_to_cap() -> void:
	var h := _make_helper()
	for x in range(6):
		h.mark_dirty(Vector2i(x, 0))
		h.world_manager.chunks[Vector2i(x, 0)] = "dummy"
	h.rebuild_dirty(h.world_manager.chunks, 0.016)
	# MAX_DISPATCH_PER_FRAME = 4
	assert_that(h.world_manager.compute_device.dispatched_coords.size()).is_equal(4)
	assert_that(h._dirty_chunks.size()).is_equal(2)


func test_on_chunk_unloaded_purges_state() -> void:
	var h := _make_helper()
	var c := Vector2i(7, 7)
	h.mark_dirty(c)
	h._in_flight = [c]
	h._pending_collision_builds = [c]
	h._pending_occluder_builds = [c]
	h._pending_segments[c] = PackedVector2Array()
	h.on_chunk_unloaded(c)
	assert_that(h._dirty_chunks.has(c)).is_false()
	assert_that(h._in_flight.has(c)).is_false()
	assert_that(h._pending_collision_builds.has(c)).is_false()
	assert_that(h._pending_occluder_builds.has(c)).is_false()
	assert_that(h._pending_segments.has(c)).is_false()
