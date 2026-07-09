extends GdUnitTestSuite


func _lobber_at(origin: Vector2, player_pos: Vector2) -> LobberEnemy:
	var e: LobberEnemy = auto_free(LobberEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_lobber_defaults_to_flame_lobber_weapon() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	assert_bool(e.weapon != null).is_true()


func test_lobber_sets_reposition_target_after_attack() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.ATTACK
	e._change_state(Enemy.State.COOLDOWN)
	assert_bool(e._has_reposition_target).is_true()
	assert_float(e._reposition_target.x).is_less(0.0)


func test_lobber_moves_toward_reposition_target_during_chase() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	e._has_reposition_target = true
	e._reposition_target = Vector2(-80, 0)
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.LEFT)).is_greater(0.99)


func test_lobber_clears_reposition_target_on_arrival() -> void:
	var e := _lobber_at(Vector2.ZERO, Vector2(200, 0))
	e._has_reposition_target = true
	e._reposition_target = Vector2(2, 0)
	e._process_chase(0.016)
	assert_bool(e._has_reposition_target).is_false()


func test_scene_instantiates_as_lobber_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/lobber_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is LobberEnemy).is_true()
