# tests/unit/test_walkability_invariant.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256
const TARGET_RADIUS := 75

func test_invariant_holds_across_biomes_and_seeds() -> void:
	var failures: Array[String] = []
	for biome_idx in range(BiomeRegistry.biomes.size()):
		LevelManager.current_biome = BiomeRegistry.biomes[biome_idx]
		for seed_val in [1, 42, 1337, 9001]:
			LevelManager.world_seed = seed_val
			var wm := _spawn_world_manager()
			wm.tracking_position = Vector2(CHUNK_SIZE * 3, CHUNK_SIZE * 3)
			await _wait_for_chunks(wm, 30)
			for cx in range(2, 5):
				for cy in range(2, 5):
					var coord := Vector2i(cx, cy)
					if not wm.chunks.has(coord):
						continue
					var max_r := _measure_max_inscribed_radius(wm, coord)
					if max_r < TARGET_RADIUS:
						failures.append("biome=%d seed=%d chunk=%s max_r=%d" % [biome_idx, seed_val, str(coord), max_r])
			wm.queue_free()
	assert_that(failures).is_empty()

func _spawn_world_manager() -> Node2D:
	var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
	add_child(wm)
	return wm

func _wait_for_chunks(wm: Node2D, frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame

func _measure_max_inscribed_radius(wm: Node2D, coord: Vector2i) -> int:
	var rect := Rect2i(coord * CHUNK_SIZE, Vector2i(CHUNK_SIZE, CHUNK_SIZE))
	var data := wm.read_region(rect)
	var best := 0
	var step := 8
	for y in range(0, CHUNK_SIZE, step):
		for x in range(0, CHUNK_SIZE, step):
			if data[y * CHUNK_SIZE + x] != MaterialRegistry.MAT_AIR:
				continue
			var r := _chebyshev_to_nearest_solid(data, x, y)
			if r > best:
				best = r
	return best

func _chebyshev_to_nearest_solid(data: PackedByteArray, x: int, y: int) -> int:
	for r in range(1, 128):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if max(abs(dx), abs(dy)) != r:
					continue
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or nx >= CHUNK_SIZE or ny < 0 or ny >= CHUNK_SIZE:
					return r
				if data[ny * CHUNK_SIZE + nx] != MaterialRegistry.MAT_AIR:
					return r
	return 128
