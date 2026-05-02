extends GdUnitTestSuite

const TICK_COUNT := 200
const WORLD_SEED := 0xC0FFEE
const EXPECTED_SHA256 := "7e1871445941fc54e51f1d04118ed93084777b3ad406c6ca0dda5755cc205d19"

func _wire_neighbors(chunks: Dictionary) -> void:
	for coord in chunks.keys():
		var c: Chunk = chunks[coord]
		var up: Vector2i = coord + Vector2i(0, -1)
		var dn: Vector2i = coord + Vector2i(0, 1)
		var lf: Vector2i = coord + Vector2i(-1, 0)
		var rt: Vector2i = coord + Vector2i(1, 0)
		if chunks.has(up): c.set_neighbor_up(chunks[up])
		if chunks.has(dn): c.set_neighbor_down(chunks[dn])
		if chunks.has(lf): c.set_neighbor_left(chunks[lf])
		if chunks.has(rt): c.set_neighbor_right(chunks[rt])

func _inject_lava_blob(chunk: Chunk, center: Vector2i, radius: int) -> void:
	var bytes := chunk.get_cells_data()
	var sz := Chunk.get_chunk_size()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := center.x + dx
			var y := center.y + dy
			if x < 0 or x >= sz or y < 0 or y >= sz:
				continue
			var idx := (y * sz + x) * 4
			bytes[idx + 0] = 4
			bytes[idx + 1] = 200
			bytes[idx + 2] = 220
			bytes[idx + 3] = 0x88
	chunk.set_cells_data(bytes)
	chunk.dirty_rect = Rect2i(center.x - radius, center.y - radius,
			radius * 2 + 1, radius * 2 + 1)
	chunk.sleeping = false

func test_snapshot_after_200_ticks() -> void:
	var sim: Simulator = Simulator.new()
	sim.set_world_seed(WORLD_SEED)

	var chunks := {}
	for cx in range(2):
		for cy in range(2):
			var c: Chunk = Chunk.new()
			c.coord = Vector2i(cx, cy)
			chunks[c.coord] = c
	_wire_neighbors(chunks)
	sim.set_chunks(chunks)

	_inject_lava_blob(chunks[Vector2i(0, 0)], Vector2i(128, 128), 16)

	for i in TICK_COUNT:
		sim.tick()

	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for coord in chunks.keys():
		ctx.update(chunks[coord].get_cells_data())
	var got := ctx.finish().hex_encode()

	if EXPECTED_SHA256 == "":
		prints("RECORD:", got)
	else:
		assert_that(got).is_equal(EXPECTED_SHA256)
