extends GdUnitTestSuite


func test_evolving_edge_doubles_after_fifteen_hits() -> void:
	var m := EvolvingEdgeModifier.new()
	assert_float(m.get_stat_add("damage")).is_equal(2.0)
	for i in range(15):
		m.on_hit_target(null, null, null)
	assert_float(m.get_stat_add("damage")).is_equal(4.0)
	assert_float(m.get_stat_add("cooldown")).is_equal(0.0)
