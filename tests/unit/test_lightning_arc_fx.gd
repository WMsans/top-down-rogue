extends GdUnitTestSuite

func test_play_spawns_fx_node_under_host() -> void:
	var host: Node2D = auto_free(Node2D.new())
	add_child(host)
	LightningArcFX.play(host, Vector2.ZERO, Vector2(40, 0), Color(0.9, 0.95, 1.0))
	assert_int(host.get_child_count()).is_equal(1)
	assert_bool(host.get_child(0) is LightningArcFX).is_true()

func test_play_null_host_is_noop() -> void:
	# must not crash
	LightningArcFX.play(null, Vector2.ZERO, Vector2(10, 0), Color.WHITE)
	assert_bool(true).is_true()
