extends GdUnitTestSuite


func _archer_at(origin: Vector2, player_pos: Vector2) -> ArcherEnemy:
	var e: ArcherEnemy = auto_free(ArcherEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_archer_uses_default_ranged_stats() -> void:
	var e := _archer_at(Vector2.ZERO, Vector2(200, 0))
	assert_int(e.max_health).is_equal(20)


func test_archer_retreats_earlier_than_preferred_distance() -> void:
	var e := _archer_at(Vector2.ZERO, Vector2(100, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.dot(Vector2.RIGHT)).is_less(0.0)


func test_archer_retreat_speed_is_boosted() -> void:
	var e := _archer_at(Vector2.ZERO, Vector2(100, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.length()).is_greater_equal(e.speed * 1.19)


func test_scene_instantiates_as_archer_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/archer_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is ArcherEnemy).is_true()
