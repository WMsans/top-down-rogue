extends GdUnitTestSuite

func test_settled_lava_puddle_chunk_sleeps_within_30_ticks() -> void:
	var sim: Simulator = Simulator.new()
	sim.set_world_seed(0xBEEF)

	var chunks := {}
	var c: Chunk = Chunk.new()
	c.coord = Vector2i(0, 0)
	chunks[c.coord] = c
	sim.set_chunks(chunks)

	var bytes := c.get_cells_data()
	var sz := Chunk.get_chunk_size()
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var x := 128 + dx
			var y := 128 + dy
			var idx := (y * sz + x) * 4
			bytes[idx + 0] = 4
			bytes[idx + 1] = 100
			bytes[idx + 2] = 200
			bytes[idx + 3] = 0x88
	c.set_cells_data(bytes)
	c.dirty_rect = Rect2i(125, 125, 7, 7)
	c.sleeping = false

	for i in 30:
		sim.tick()

	assert_that(c.sleeping).is_true()
