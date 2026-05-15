# tests/unit/test_walkability_connectivity.gd
extends GdUnitTestSuite

const CHUNK_SIZE := 256

func test_air_is_well_connected() -> void:
	LevelManager.current_biome = BiomeRegistry.biomes[0]
	LevelManager.world_seed = 12345
	var wm: Node2D = preload("res://scenes/world_manager.tscn").instantiate()
	add_child(wm)
	wm.tracking_position = Vector2(CHUNK_SIZE * 4, CHUNK_SIZE * 4)
	for _i in range(30):
		await get_tree().process_frame

	var rect := Rect2i(CHUNK_SIZE * 2, CHUNK_SIZE * 2, CHUNK_SIZE * 4, CHUNK_SIZE * 4)
	var data := wm.read_region(rect)
	var w := rect.size.x
	var h := rect.size.y
	var visited := PackedByteArray()
	visited.resize(w * h)

	var total_air := 0
	var largest_component := 0
	for y in range(h):
		for x in range(w):
			if visited[y * w + x] != 0:
				continue
			if data[y * w + x] != MaterialRegistry.MAT_AIR:
				continue
			var size := _flood_fill(data, visited, w, h, x, y)
			total_air += size
			if size > largest_component:
				largest_component = size

	var ratio := float(largest_component) / float(max(1, total_air))
	wm.queue_free()
	assert_that(ratio).is_greater_equal(0.95)

func _flood_fill(data: PackedByteArray, visited: PackedByteArray, w: int, h: int, sx: int, sy: int) -> int:
	var stack: Array[Vector2i] = [Vector2i(sx, sy)]
	var size := 0
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.x >= w or p.y < 0 or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		if data[idx] != MaterialRegistry.MAT_AIR:
			continue
		visited[idx] = 1
		size += 1
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	return size
