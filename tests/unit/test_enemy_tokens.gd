extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockEnemy extends Enemy:
	var sight: bool = true
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return sight


var _world: FakeWorld


func before_test() -> void:
	_world = auto_free(FakeWorld.new())
	add_child(_world)


func _make(player_pos: Vector2) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = _world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 32.0
	e._state = Enemy.State.CHASE
	return e


func _tick_director(e: Enemy) -> void:
	_world.encounter_director.update(e._player_ref.global_position, [e])


func test_waits_for_token_before_windup() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	_tick_director(e)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_no_director_attacks_immediately() -> void:
	var e := _make(Vector2(20, 0))
	e._world_manager = null
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_uses_tokens_false_bypasses_pool() -> void:
	var e := _make(Vector2(20, 0))
	e.uses_tokens = false
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_attack_marks_token_attacking() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._change_state(Enemy.State.ATTACK)
	_world.encounter_director.update(Vector2(20, 0), [e], 5.0)
	assert_bool(_world.encounter_director.has_token(e)).is_true()


func test_recover_exit_releases_token() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._change_state(Enemy.State.RECOVER)
	assert_bool(_world.encounter_director.has_token(e)).is_true()
	e._change_state(Enemy.State.CHASE)
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_elite_hit_during_windup_cancels_and_releases() -> void:
	var e := _make(Vector2(20, 0))
	e.is_elite = true
	e.max_hits = 2
	e.hits_remaining = 2
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	e.take_hit()
	assert_int(e._state).is_equal(Enemy.State.HURT)
	assert_bool(_world.encounter_director.has_token(e)).is_false()
	e._state_timer = 0.0
	e._process_hurt(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_stun_during_windup_cancels_and_releases() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e._status_component.add_timed_status("stun", 0.5)
	e._process(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_disabled_enemy_cannot_take_token() -> void:
	var e := _make(Vector2(20, 0))
	e._aggroed = true
	e._process_chase(0.016)
	_tick_director(e)
	# Precondition: the director would hand this enemy a token right now.
	assert_bool(_world.encounter_director.has_token(e)).is_true()
	e._status_component.add_timed_status("stun", 0.5)
	assert_bool(e._try_take_token()).is_false()
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_losing_sight_in_windup_returns_to_chase_keeping_aggro() -> void:
	var e := _make(Vector2(20, 0))
	e._process_chase(0.016)
	_tick_director(e)
	e._process_chase(0.016)
	e.sight = false
	e._process_windup(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_bool(e._aggroed).is_true()
	assert_bool(_world.encounter_director.has_token(e)).is_false()


func test_ranged_costs_half_token() -> void:
	var r: RangedEnemy = auto_free(RangedEnemy.new())
	add_child(r)
	assert_float(r.token_cost()).is_equal(0.5)
