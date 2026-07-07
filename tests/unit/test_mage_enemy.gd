extends GdUnitTestSuite


func _mage_at(origin: Vector2, player_pos: Vector2) -> MageEnemy:
	var e: MageEnemy = auto_free(MageEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	return e


func test_mage_has_reduced_health() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_int(e.max_health).is_equal(18)  # int(20 * 0.9) = 18


func test_mage_has_reduced_speed() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_float(e.speed).is_equal_approx(50.0 * 0.6, 0.5)


func test_mage_defaults_to_seeker_launcher_weapon() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	assert_bool(e.weapon != null).is_true()


func test_mage_walks_straight_toward_player_when_out_of_range() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(300, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.RIGHT)).is_greater(0.99)


func test_mage_stops_moving_once_in_attack_range() -> void:
	var e := _mage_at(Vector2.ZERO, Vector2(50, 0))
	e._state = Enemy.State.CHASE
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_vector(e.velocity).is_equal(Vector2.ZERO)


func test_scene_instantiates_as_mage_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/mage_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is MageEnemy).is_true()
