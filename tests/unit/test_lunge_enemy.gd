extends GdUnitTestSuite


func test_base_enemy_does_not_move_during_attack() -> void:
	var e: MeleeEnemy = auto_free(MeleeEnemy.new())
	add_child(e)
	assert_bool(e._moves_during_attack()).is_false()


# --- Task 2: skeleton ---

func _lunge_at(origin: Vector2, player_pos: Vector2) -> LungeEnemy:
	var e: LungeEnemy = auto_free(LungeEnemy.new())
	add_child(e)
	e.global_position = origin
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	return e

func test_ready_sets_lunge_attack_range() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	assert_float(e._attack_range).is_equal(e.lunge_range)

func test_begin_dash_locks_direction_toward_player() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._begin_dash()
	assert_float(e._lock_dir.angle()).is_equal_approx(0.0, 0.01)
	assert_float(e._dash_timer).is_equal(e.dash_duration)
	assert_bool(e._dash_hit).is_false()

func test_moves_during_attack_tracks_state_and_dash_done() -> void:
	var e := _lunge_at(Vector2.ZERO, Vector2(100, 0))
	e._state = Enemy.State.CHASE
	assert_bool(e._moves_during_attack()).is_false()
	e._state = Enemy.State.ATTACK
	e._dash_done = false
	assert_bool(e._moves_during_attack()).is_true()
	e._dash_done = true
	assert_bool(e._moves_during_attack()).is_false()
