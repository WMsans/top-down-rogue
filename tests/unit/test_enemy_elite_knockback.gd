extends GdUnitTestSuite

class MockEnemy extends Enemy:
	pass

func test_non_elite_enemy_gets_full_knockback() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.is_elite = false
	e._knockback_velocity = Vector2.ZERO
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(100.0, 0.01)

func test_elite_enemy_gets_reduced_knockback() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.is_elite = true
	e._knockback_velocity = Vector2.ZERO
	e.apply_knockback(Vector2.RIGHT, 100.0)
	assert_float(e._knockback_velocity.length()).is_equal_approx(40.0, 0.01)
