extends GdUnitTestSuite


func _make(tier: int, player_pos: Vector2, player_vel: Vector2 = Vector2.ZERO) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	e.enemy_tier = tier
	add_child(e)
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = player_pos
	p.velocity = player_vel
	e._player_ref = p
	return e


func test_dash_aims_at_predicted_position() -> void:
	var e := _make(DropTable.EnemyTier.HARD, Vector2(105, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	e._begin_dash()
	var travel := 105.0 / e.dash_speed
	var expected := Vector2(105, 100 * travel).normalized()
	assert_float(e._lock_dir.angle()).is_equal_approx(expected.angle(), 0.001)


func test_easy_dash_aims_at_current_position() -> void:
	var e := _make(DropTable.EnemyTier.EASY, Vector2(100, 0), Vector2(0, 100))
	e._begin_dash()
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.001)


func test_redirect_capped_at_30_degrees() -> void:
	var e := _make(DropTable.EnemyTier.HARD, Vector2(100, 0))
	e._get_profile().lead_factor = 0.0
	e._state = Enemy.State.ATTACK
	e._begin_dash()
	e._player_ref.global_position = e.global_position + Vector2(0, 100)
	e._tick_dash(e.dash_duration * 0.5 + 0.001)
	e._tick_dash(0.001)
	assert_bool(e._redirected).is_true()
	assert_float(e._lock_dir.angle()).is_equal_approx(PI / 6.0, 0.01)


func test_no_redirect_when_profile_disables_it() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(100, 0))
	e._get_profile().lead_factor = 0.0
	e._state = Enemy.State.ATTACK
	e._begin_dash()
	e._player_ref.global_position = e.global_position + Vector2(0, 100)
	e._tick_dash(e.dash_duration * 0.5 + 0.001)
	e._tick_dash(0.001)
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.001)


func test_cancel_mid_dash_stops_dash() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(100, 0))
	e.is_elite = true
	e.max_hits = 2
	e.hits_remaining = 2
	e._state = Enemy.State.ATTACK
	e._attack_started = false
	e._dash_done = false
	e._process_attack(0.016)
	e.take_hit()
	assert_bool(e._dash_done).is_true()
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	e._state_timer = 0.0
	e._process_hurt(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
