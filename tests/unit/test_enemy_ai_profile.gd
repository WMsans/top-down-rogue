extends GdUnitTestSuite

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass

class MockPlayer extends Node2D:
	var targeted_enemy: Node2D = null


func _make(tier: int, elite: bool = false) -> MockEnemy:
	var e: MockEnemy = auto_free(MockEnemy.new())
	e.enemy_tier = tier
	e.is_elite = elite
	add_child(e)
	return e


func test_profile_built_from_tier() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	assert_float(e.profile.telegraph_mult).is_equal(0.75)


func test_elite_profile_steps_up() -> void:
	var e := _make(DropTable.EnemyTier.EASY, true)
	assert_float(e.profile.telegraph_mult).is_equal(1.0)


func test_windup_scales_with_telegraph() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	e.windup_duration = 0.4
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.3, 0.0001)


func test_fast_elite_windup_never_below_floor() -> void:
	for tier in [DropTable.EnemyTier.NORMAL, DropTable.EnemyTier.HARD]:
		var e: MockEnemy = auto_free(MockEnemy.new())
		e.enemy_tier = tier
		e.is_elite = true
		e.elite_ability = Enemy.EliteAbility.FAST
		add_child(e)
		assert_float(e.windup_duration).is_equal_approx(0.2, 0.0001)
		e._change_state(Enemy.State.WINDUP)
		assert_float(e._state_timer).is_greater_equal(0.15)


func test_recover_scales_with_cadence() -> void:
	var e := _make(DropTable.EnemyTier.EASY)
	e.cooldown_duration = 1.0
	e._change_state(Enemy.State.RECOVER)
	assert_float(e._state_timer).is_equal_approx(1.2, 0.0001)


func test_get_profile_safe_before_ready() -> void:
	var e: MockEnemy = auto_free(MockEnemy.new())
	assert_object(e._get_profile()).is_not_null()


func test_attack_end_goes_to_recover() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_speed_ignores_player_targeting() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e.speed = 100.0
	# The player targets someone else; the old code slowed this enemy to 0.7x.
	var other: Node2D = auto_free(Node2D.new())
	add_child(other)
	var p: MockPlayer = auto_free(MockPlayer.new())
	p.targeted_enemy = other
	add_child(p)
	e._player_ref = p
	assert_float(e._get_effective_speed()).is_equal(100.0)
