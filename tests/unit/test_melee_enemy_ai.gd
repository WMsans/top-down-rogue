extends GdUnitTestSuite

class CountingWeapon extends MeleeWeapon:
	var uses: int = 0
	func _use_impl(_user: Node) -> void:
		uses += 1

class MockMelee extends MeleeEnemy:
	var real_attack: bool = false
	func _can_see_player() -> bool:
		return true
	func _execute_attack() -> void:
		if real_attack:
			super._execute_attack()


func _make(tier: int, player_pos: Vector2) -> MockMelee:
	var e: MockMelee = auto_free(MockMelee.new())
	e.enemy_tier = tier
	add_child(e)
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	p.global_position = player_pos
	e._player_ref = p
	e._attack_range = 28.0
	return e


func test_windup_tracks_then_locks() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e.windup_duration = 0.35
	e._change_state(Enemy.State.WINDUP)
	e._process_windup(0.1)
	assert_float(e.get_facing_direction().angle()).is_equal_approx(0.0, 0.01)
	e._player_ref.global_position = Vector2(0, 20)
	assert_float(e.get_facing_direction().angle()).is_equal_approx(PI / 2.0, 0.01)
	e._process_windup(0.16)  # timer 0.09 -> inside lock window next tick
	e._process_windup(0.01)
	assert_bool(e._aim_locked).is_true()
	var locked := e.get_facing_direction()
	e._player_ref.global_position = Vector2(-20, 0)
	assert_that(e.get_facing_direction()).is_equal(locked)


func test_lock_cleared_on_recover() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._aim_locked = true
	e._change_state(Enemy.State.RECOVER)
	assert_bool(e._aim_locked).is_false()


func test_normal_chains_one_follow_up() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.2, 0.0001)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_chain_steps_toward_player() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(30, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_float(e.global_position.x).is_equal_approx(16.0, 0.01)


func test_easy_does_not_chain() -> void:
	var e := _make(DropTable.EnemyTier.EASY, Vector2(20, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_no_chain_when_player_out_of_reach() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(80, 0))
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(e._state).is_equal(Enemy.State.RECOVER)


func test_chain_second_swing_fires_despite_weapon_cooldown() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	var w := CountingWeapon.new()
	w.cooldown = 5.0
	e.weapon = w
	e.real_attack = true
	e._change_state(Enemy.State.WINDUP)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	e._change_state(Enemy.State.ATTACK)
	e._process_attack(0.0)
	assert_int(w.uses).is_equal(2)


func test_fresh_windup_resets_swing_count() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, Vector2(20, 0))
	e._swings_done = 2
	e._change_state(Enemy.State.WINDUP)
	assert_int(e._swings_done).is_equal(0)
