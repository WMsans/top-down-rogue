extends GdUnitTestSuite

func _player_at(pos: Vector2) -> Node2D:
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = pos
	return p

func test_facing_tracks_player_before_lock() -> void:
	var s: SniperEnemy = auto_free(SniperEnemy.new())
	add_child(s)
	s.global_position = Vector2.ZERO
	s._player_ref = _player_at(Vector2(100, 0))
	assert_float(s.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)

func test_facing_returns_locked_direction_after_lock() -> void:
	var s: SniperEnemy = auto_free(SniperEnemy.new())
	add_child(s)
	s.global_position = Vector2.ZERO
	s._player_ref = _player_at(Vector2(100, 0))
	s._lock_aim()
	s._player_ref.global_position = Vector2(0, 100)
	assert_bool(s._aim_locked).is_true()
	assert_float(s.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)