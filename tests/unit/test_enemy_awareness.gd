extends GdUnitTestSuite

class MockEnemy extends Enemy:
	var sight: bool = true
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return sight


func _make(pos: Vector2 = Vector2.ZERO) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e.global_position = pos
	return e


func _moving_player(pos: Vector2, vel: Vector2) -> CharacterBody2D:
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = pos
	p.velocity = vel
	return p


func test_predict_scales_with_lead() -> void:
	var e := _make()
	e._player_ref = _moving_player(Vector2(100, 0), Vector2(0, 50))
	e._get_profile().lead_factor = 0.0
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 0))
	e.profile.lead_factor = 0.5
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 25))
	e.profile.lead_factor = 1.0
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(100, 50))


func test_predict_without_velocity_is_current_position() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(30, 40)
	e._player_ref = p
	assert_that(e._predict_player_pos(2.0)).is_equal(Vector2(30, 40))


func test_predict_without_player_returns_self_position() -> void:
	var e := _make(Vector2(7, 9))
	e._player_ref = null
	assert_that(e._predict_player_pos(1.0)).is_equal(Vector2(7, 9))
	assert_that(e._dir_to_predicted(100.0)).is_equal(Vector2.DOWN)


func test_dir_to_predicted_uses_travel_time() -> void:
	var e := _make()
	e._player_ref = _moving_player(Vector2(100, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	# travel = 100px / 100px/s = 1s -> aim at (100, 100)
	var d := e._dir_to_predicted(100.0)
	assert_float(d.angle()).is_equal_approx(PI / 4.0, 0.001)
	assert_that(e._debug_aim_point).is_equal(Vector2(100, 100))


func test_reaction_delay_holds_chase() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(100, 0)
	e._player_ref = p
	e._player_in_range = true
	e._get_profile().reaction_time = 0.2
	e._process_idle(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	e._process_chase(0.1)
	assert_that(e.velocity).is_equal(Vector2.ZERO)
	e._process_chase(0.15)
	e._process_chase(0.016)
	assert_float(e.velocity.length()).is_greater(0.0)


func test_alert_reaches_only_nearby() -> void:
	var src := _make(Vector2.ZERO)
	var near := _make(Vector2(100, 0))
	var far := _make(Vector2(200, 0))
	EncounterDirector.alert(Vector2.ZERO, 120.0, [src, near, far], src)
	assert_float(near._alert_timer).is_greater_equal(0.0)
	assert_float(far._alert_timer).is_less(0.0)
	assert_float(src._alert_timer).is_less(0.0)


func test_alerted_enemy_aggroes_after_reaction_time() -> void:
	var e := _make()
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(300, 0)
	e._player_ref = p
	e._player_in_range = false
	e._get_profile().reaction_time = 0.2
	e.receive_alert()
	e._process_idle(0.1)
	assert_int(e._state).is_equal(Enemy.State.WANDER)
	e._process_idle(0.15)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(e._aggroed).is_true()


func test_first_sight_broadcasts_alert() -> void:
	var seer := _make(Vector2.ZERO)
	var buddy := _make(Vector2(80, 0))
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = Vector2(40, 0)
	seer._player_ref = p
	seer._player_in_range = true
	seer._state = Enemy.State.CHASE
	seer._process_chase(0.016)
	assert_float(buddy._alert_timer).is_greater_equal(0.0)
