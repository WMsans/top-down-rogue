extends GdUnitTestSuite


class FakeWorldManager:
	extends Node2D
	var chunks: Dictionary = {}


func test_query_empty_cache_returns_default_cell() -> void:
	var tp := TerrainPhysical.new()
	var cell := tp.query(Vector2(50, 60))
	assert_that(cell.material_id).is_equal(0)
	assert_that(cell.is_solid).is_false()
	assert_that(cell.damage).is_equal(0.0)


func test_query_queues_pending_probe() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(12.7, -3.2))
	assert_that(tp._pending_probes.has(Vector2i(12, -4))).is_true()


func test_apply_probe_results_populates_cache() -> void:
	var tp := TerrainPhysical.new()
	# Queue one probe via query (returns default).
	tp.query(Vector2(10, 20))

	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(10, 20)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.MAT_STONE)
	tp.apply_probe_results(batch, raw)

	var cell := tp.query(Vector2(10, 20))
	assert_that(cell.material_id).is_equal(MaterialRegistry.MAT_STONE)


func test_ttl_expiry_returns_default() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(5, 5))
	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(5, 5)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.MAT_STONE)
	tp.apply_probe_results(batch, raw)

	# Advance frame counter past TTL by applying empty batches.
	for i in range(TerrainPhysical.TTL_FRAMES + 1):
		tp.apply_probe_results([], PackedByteArray())

	var cell := tp.query(Vector2(5, 5))
	assert_that(cell.material_id).is_equal(0)


func test_invalidate_clears_cache_entry() -> void:
	var tp := TerrainPhysical.new()
	tp.query(Vector2(15, 25))
	var batch: Array = [{
		"chunk_coord": Vector2i(0, 0),
		"world_coords": [Vector2i(15, 25)],
		"start": 0,
		"count": 1,
	}]
	var raw := PackedByteArray()
	raw.resize(4)
	raw.encode_u32(0, MaterialRegistry.MAT_STONE)
	tp.apply_probe_results(batch, raw)

	tp.invalidate_rect(Rect2i(10, 20, 10, 10))

	var cell := tp.query(Vector2(15, 25))
	assert_that(cell.material_id).is_equal(0)


func test_set_center_updates_grid_center() -> void:
	var tp := TerrainPhysical.new()
	tp.set_center(Vector2i(500, 500))
	assert_that(tp._grid_center).is_equal(Vector2i(500, 500))


func test_prepare_probe_batch_bins_by_chunk() -> void:
	var tp := TerrainPhysical.new()
	# Stub world_manager with a chunks dict containing two chunk coords.
	var fake_wm := FakeWorldManager.new()
	fake_wm.chunks = {Vector2i(0, 0): true, Vector2i(1, 0): true}
	tp.world_manager = fake_wm

	tp.query(Vector2(5, 5))      # chunk (0,0) local (5,5)
	tp.query(Vector2(260, 10))   # chunk (1,0) local (4,10)
	tp.query(Vector2(7, 8))      # chunk (0,0) local (7,8)

	var batch: Array = tp.prepare_probe_batch()

	# Two chunks present in batch.
	assert_that(batch.size()).is_equal(2)

	var total: int = 0
	for entry: Dictionary in batch:
		total += int(entry["count"])
	assert_that(total).is_equal(3)

	# Starts are contiguous.
	var sorted_starts: Array = []
	for entry in batch:
		sorted_starts.append(int(entry["start"]))
	sorted_starts.sort()
	assert_that(sorted_starts[0]).is_equal(0)
	assert_that(sorted_starts[1]).is_equal(int(batch[0]["count"]) if int(batch[0]["start"]) == 0 else int(batch[1]["count"]))

	fake_wm.free()


func test_prepare_probe_batch_drops_unloaded_chunks() -> void:
	var tp := TerrainPhysical.new()
	var fake_wm := FakeWorldManager.new()
	fake_wm.chunks = {Vector2i(0, 0): true}  # chunk (1,0) NOT loaded
	tp.world_manager = fake_wm

	tp.query(Vector2(5, 5))      # in loaded chunk
	tp.query(Vector2(260, 10))   # in unloaded chunk

	var batch: Array = tp.prepare_probe_batch()
	assert_that(batch.size()).is_equal(1)
	assert_that(batch[0]["chunk_coord"]).is_equal(Vector2i(0, 0))
	assert_that(int(batch[0]["count"])).is_equal(1)
	# Pending set is fully drained (unloaded probes are discarded, not retained).
	assert_that(tp._pending_probes.is_empty()).is_true()

	fake_wm.free()
