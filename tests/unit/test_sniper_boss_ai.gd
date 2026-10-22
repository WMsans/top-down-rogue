extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null


func _player(pos: Vector2, vel: Vector2) -> CharacterBody2D:
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = pos
	p.velocity = vel
	return p


func test_sniper_locks_on_predicted_direction() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	e._player_ref = _player(Vector2(200, 0), Vector2(0, 100))
	e._get_profile().lead_factor = 1.0
	e._lock_aim()
	var spd := (e.weapon as RangedWeapon).projectile_speed
	var expected := Vector2(200, 100.0 * 200.0 / spd).normalized()
	assert_float(e._lock_dir.angle()).is_equal_approx(expected.angle(), 0.001)


func test_sniper_has_no_volley_bonus() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	var base := SniperWeapon.new()
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(base.burst_count)
	assert_int((e.weapon as RangedWeapon).projectile_count).is_equal(base.projectile_count)


func test_sniper_windup_scales() -> void:
	var e: SniperEnemy = auto_free(SniperEnemy.new())
	e.enemy_tier = DropTable.EnemyTier.HARD
	add_child(e)
	e._change_state(Enemy.State.WINDUP)
	assert_float(e._state_timer).is_equal_approx(0.6375, 0.0001)


func test_boss_uses_hard_profile() -> void:
	var b: BossEnemy = auto_free(BossEnemy.new())
	b.enemy_tier = DropTable.EnemyTier.EASY
	add_child(b)
	assert_float(b.profile.cadence_mult).is_equal(0.7)
	assert_float(b.profile.lead_factor).is_equal(0.9)


func test_boss_attacks_without_token() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var b: BossEnemy = auto_free(BossEnemy.new())
	add_child(b)
	b._world_manager = world
	b._director = null
	b._player_ref = _player(Vector2(50, 0), Vector2.ZERO)
	b._player_in_range = true
	b._aggroed = true
	b._state = Enemy.State.CHASE
	b._process_chase(0.016)
	assert_int(b._state).is_equal(Enemy.State.WINDUP)
	assert_float(world.encounter_director.used_tokens()).is_equal(0.0)


func test_boss_leads_shots() -> void:
	var b: BossEnemy = auto_free(BossEnemy.new())
	add_child(b)
	b._player_ref = _player(Vector2(100, 0), Vector2(0, 100))
	assert_float(b.get_facing_direction().y).is_greater(0.0)
