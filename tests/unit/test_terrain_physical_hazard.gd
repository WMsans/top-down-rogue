extends GdUnitTestSuite

class FakeChunk:
	var hazard_cells: PackedInt32Array = PackedInt32Array()
	func _init() -> void:
		hazard_cells.resize(16)
		hazard_cells.fill(0)

class FakeWorldManager extends Node2D:
	var chunks: Dictionary = {}

func test_hazard_at_returns_false_for_unloaded_chunk() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_LAVA)).is_false()
	wm.queue_free()

func test_hazard_at_returns_true_when_mask_matches() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	var chunk := FakeChunk.new()
	# cell (0,0) of chunk (0,0). Sub-cell size 64; pixel (10,10) is in sub-cell index 0.
	chunk.hazard_cells[0] = MaterialRegistry.HAZARD_LAVA
	wm.chunks[Vector2i(0, 0)] = chunk
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_LAVA)).is_true()
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_FIRE)).is_false()
	wm.queue_free()

func test_hazard_at_maps_to_correct_sub_cell() -> void:
	var tp := TerrainPhysical.new()
	var wm := FakeWorldManager.new()
	tp.world_manager = wm
	add_child(wm)
	var chunk := FakeChunk.new()
	# Sub-cell at local (3,2) = idx 2*4+3 = 11. Pixel (3*64+10, 2*64+10) = (202, 138).
	chunk.hazard_cells[11] = MaterialRegistry.HAZARD_OIL
	wm.chunks[Vector2i(0, 0)] = chunk
	assert_bool(tp.hazard_at(Vector2(202, 138), MaterialRegistry.HAZARD_OIL)).is_true()
	assert_bool(tp.hazard_at(Vector2(10, 10), MaterialRegistry.HAZARD_OIL)).is_false()
	wm.queue_free()
