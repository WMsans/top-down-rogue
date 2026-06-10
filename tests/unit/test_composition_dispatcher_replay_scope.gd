extends GdUnitTestSuite

# Regression: replaying a stamp because a NEW chunk loaded must only write into
# that new chunk, never into already-loaded (possibly player-edited) chunks.
# Previously the whole ring/blob was re-applied across every loaded chunk it
# overlapped, healing carved holes in chunks that never left view.

const _Dispatcher = preload("res://src/core/composition_dispatcher.gd")
const CHUNK_SIZE := 256


class FakeWorldManager:
	extends Node
	var ring_calls: Array = []
	var blob_calls: Array = []

	func place_material_ring(world_pos: Vector2, inner: float, outer: float, mat: int, only_chunks: Dictionary = {}) -> void:
		ring_calls.append({"pos": world_pos, "inner": inner, "outer": outer, "mat": mat, "only": only_chunks})

	func place_material_blob(world_pos: Vector2, radius: float, mat: int, seed_v: int, jitter: float, only_chunks: Dictionary = {}) -> void:
		blob_calls.append({"pos": world_pos, "radius": radius, "mat": mat, "only": only_chunks})


func test_replay_restricts_ring_to_new_chunks() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var fake := FakeWorldManager.new()
	add_child(fake)
	dispatcher._world_manager = fake

	# Ring centred on the boundary of chunks (0,0) and (1,0) so it straddles both.
	dispatcher._stamps.append({
		"kind": "ring",
		"pos": Vector2(CHUNK_SIZE, 64),
		"inner": 40.0,
		"outer": 60.0,
		"mat": 7,
	})

	# Only chunk (1,0) newly generated; (0,0) is already loaded (and maybe edited).
	dispatcher._replay_stamps_for_chunks([Vector2i(1, 0)] as Array[Vector2i])

	assert_int(fake.ring_calls.size()).is_equal(1)
	var only: Dictionary = fake.ring_calls[0]["only"]
	assert_bool(only.has(Vector2i(1, 0))).is_true()
	assert_bool(only.has(Vector2i(0, 0))).is_false()


func test_replay_skips_stamp_not_touching_new_chunks() -> void:
	var dispatcher = _Dispatcher.new()
	add_child(dispatcher)
	var fake := FakeWorldManager.new()
	add_child(fake)
	dispatcher._world_manager = fake

	# Ring fully inside chunk (0,0); new chunk (5,5) is far away.
	dispatcher._stamps.append({
		"kind": "ring",
		"pos": Vector2(128, 128),
		"inner": 40.0,
		"outer": 60.0,
		"mat": 7,
	})

	dispatcher._replay_stamps_for_chunks([Vector2i(5, 5)] as Array[Vector2i])

	assert_int(fake.ring_calls.size()).is_equal(0)
