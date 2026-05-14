extends GdUnitTestSuite

class MockPlayer extends Node2D:
	var targeted_enemy: Node2D = null

class MockAggroEnemy extends Enemy:
	func _execute_attack() -> void:
		pass

func _make_player(target: Node2D = null) -> MockPlayer:
	var p: MockPlayer = auto_free(MockPlayer.new())
	p.add_to_group("player")
	p.targeted_enemy = target
	add_child(p)
	return p

func test_is_targeted_returns_true_when_targeted() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	_make_player(e)
	assert_that(e._is_targeted()).is_true()

func test_is_targeted_returns_false_when_not_targeted() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	var other := auto_free(MockAggroEnemy.new())
	add_child(other)
	_make_player(other)
	assert_that(e._is_targeted()).is_false()

func test_is_targeted_returns_false_when_no_player() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	assert_that(e._is_targeted()).is_false()

func test_effective_speed_targeted() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	e.speed = 100.0
	add_child(e)
	_make_player(e)
	assert_that(e._get_effective_speed()).is_equal(130.0)

func test_effective_speed_passive() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	e.speed = 100.0
	add_child(e)
	var other := auto_free(MockAggroEnemy.new())
	add_child(other)
	_make_player(other)
	assert_that(e._get_effective_speed()).is_equal(70.0)

func test_effective_speed_no_target() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	e.speed = 100.0
	add_child(e)
	_make_player(null)
	assert_that(e._get_effective_speed()).is_equal(100.0)

func test_effective_speed_no_player() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	e.speed = 100.0
	add_child(e)
	assert_that(e._get_effective_speed()).is_equal(100.0)

func test_cooldown_multiplier_targeted() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	_make_player(e)
	assert_that(e._get_cooldown_multiplier()).is_less(1.0)

func test_cooldown_multiplier_passive() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	var other := auto_free(MockAggroEnemy.new())
	add_child(other)
	_make_player(other)
	assert_that(e._get_cooldown_multiplier()).is_greater(1.0)

func test_cooldown_multiplier_no_target() -> void:
	var e: MockAggroEnemy = auto_free(MockAggroEnemy.new())
	add_child(e)
	_make_player(null)
	assert_that(e._get_cooldown_multiplier()).is_equal(1.0)
