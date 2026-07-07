extends GdUnitTestSuite


func _skirmisher_at(origin: Vector2, player_pos: Vector2) -> SkirmisherEnemy:
	var e: SkirmisherEnemy = auto_free(SkirmisherEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._aggroed = true
	return e


func test_skirmisher_has_reduced_health() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_int(e.max_health).is_equal(9)


func test_skirmisher_has_boosted_speed() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_float(e.speed).is_equal_approx(84.0, 0.5)


func test_skirmisher_has_reduced_weapon_damage() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(200, 0))
	assert_float(e.weapon.damage).is_equal_approx(MeleeWeapon.new().damage * 0.7, 0.01)


func test_skirmisher_flanks_when_far_from_commit_range() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(300, 0))
	e._flank_sign = 1.0
	e._flank_angle = deg_to_rad(60.0)
	e._process_chase(0.016)
	var to_player_dir := Vector2(300, 0).normalized()
	var dot := e.velocity.normalized().dot(to_player_dir)
	assert_float(dot).is_less(0.9)


func test_skirmisher_moves_straight_within_commit_range() -> void:
	var e := _skirmisher_at(Vector2.ZERO, Vector2(30, 0))
	e._process_chase(0.016)
	assert_float(e.velocity.normalized().dot(Vector2.RIGHT)).is_greater(0.99)


func test_scene_instantiates_as_skirmisher_enemy() -> void:
	var scene: PackedScene = load("res://scenes/enemies/skirmisher_enemy.tscn")
	assert_object(scene).is_not_null()
	var e = auto_free(scene.instantiate())
	add_child(e)
	assert_bool(e is SkirmisherEnemy).is_true()
