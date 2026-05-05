extends GdUnitTestSuite

class MockEnemy extends Enemy:
	var attack_called: bool = false
	func _execute_attack() -> void:
		attack_called = true

func test_starts_in_idle() -> void:
	var e := auto_free(MockEnemy.new())
	assert_that(e._state).is_equal(Enemy.State.IDLE)

func test_transitions_to_chase_when_player_in_range() -> void:
	var e := auto_free(MockEnemy.new())
	e._player_in_range = true
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.CHASE)

func test_transitions_to_idle_when_player_leaves() -> void:
	var e := auto_free(MockEnemy.new())
	e._player_in_range = false
	e._player_ref = Node2D.new()
	add_child(e._player_ref)
	e._player_ref.global_position = Vector2(10, 0)
	e._state = Enemy.State.CHASE
	e._process(0.1)
	assert_that(e._state).is_equal(Enemy.State.IDLE)

func test_hurt_re_staggerable() -> void:
	var e := auto_free(MockEnemy.new())
	e.health = 100
	e._state = Enemy.State.CHASE
	e._state_timer = 0.1
	e.hit(5)
	assert_that(e._state).is_equal(Enemy.State.HURT)
	var timer_after_first := e._state_timer
	e.hit(5)
	assert_that(e._state_timer).is_equal(e.hurt_duration)

func test_death_on_zero_health() -> void:
	var e := auto_free(MockEnemy.new())
	e.health = 5
	e.hit(10)
	assert_that(e._state).is_equal(Enemy.State.DEATH)

func test_elite_stat_scaling() -> void:
	var e := auto_free(MockEnemy.new())
	e.max_health = 20
	e.speed = 100.0
	e.is_elite = true
	e._ready()
	assert_that(e.max_health).is_equal(60)
	assert_that(e.speed).is_greater(100.0)

func test_elite_tank_speed() -> void:
	var e := auto_free(MockEnemy.new())
	e.max_health = 20
	e.speed = 100.0
	e._speed_base = 100.0
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.TANK
	e._ready()
	assert_that(e.speed).is_equal(70.0)

func test_elite_fast_windup_floor() -> void:
	var e := auto_free(MockEnemy.new())
	e.windup_duration = 0.3
	e.is_elite = true
	e.elite_ability = Enemy.EliteAbility.FAST
	e._ready()
	assert_that(e.windup_duration).is_equal(0.2)
