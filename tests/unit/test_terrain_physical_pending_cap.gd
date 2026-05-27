extends GdUnitTestSuite


func test_pending_caps_at_max_pending() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 8
	for i in range(20):
		tp.query(Vector2(float(i), 0.0))
	assert_int(tp._pending_probes.size()).is_less_equal(8)


func test_pending_drops_oldest_on_overflow() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 4
	tp.query(Vector2(0, 0))
	tp.query(Vector2(1, 0))
	tp.query(Vector2(2, 0))
	tp.query(Vector2(3, 0))
	tp.query(Vector2(4, 0))
	assert_bool(tp._pending_probes.has(Vector2i(0, 0))).is_false()
	assert_bool(tp._pending_probes.has(Vector2i(4, 0))).is_true()


func test_duplicate_query_does_not_grow_pending() -> void:
	var tp := TerrainPhysical.new()
	tp.MAX_PENDING = 4
	for _i in range(10):
		tp.query(Vector2(5, 5))
	assert_int(tp._pending_probes.size()).is_equal(1)
