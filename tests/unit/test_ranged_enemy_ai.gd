extends GdUnitTestSuite

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockRanged extends RangedEnemy:
	var can_see: bool = true
	func _can_see_player() -> bool:
		return can_see
	func _has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return true
	func _execute_attack() -> void:
		pass

class TerrainRanged extends RangedEnemy:
	var nav_dir: Vector2 = Vector2(0, 1)
	func _edge_blocked(_step: Vector2) -> bool:
		return true
	func _nav_field_dir() -> Vector2:
		return nav_dir
	func _execute_attack() -> void:
		pass


func _fan_weapon() -> RangedWeapon:
	var w := RangedWeapon.new()
	w.projectile_count = 3
	w.spread_angle = 30.0
	return w


func _make(tier: int, weapon: RangedWeapon = null) -> MockRanged:
	var e: MockRanged = auto_free(MockRanged.new())
	e.enemy_tier = tier
	e.weapon_resource = weapon
	add_child(e)
	var p: CharacterBody2D = auto_free(CharacterBody2D.new())
	add_child(p)
	p.global_position = Vector2(120, 0)
	e._player_ref = p
	e._player_in_range = true
	e._state = Enemy.State.CHASE
	return e


func test_volley_bonus_adds_burst_shots() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(3)


func test_volley_bonus_widens_fan() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL, _fan_weapon())
	assert_int((e.weapon as RangedWeapon).projectile_count).is_equal(4)


func test_easy_volley_unchanged() -> void:
	var e := _make(DropTable.EnemyTier.EASY)
	assert_int((e.weapon as RangedWeapon).burst_count).is_equal(1)


func test_chase_without_spot_repositions() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.REPOSITION)
	assert_float(e._reposition_target.distance_to(Vector2(120, 0))).is_between(100.0, 150.0)


func test_reposition_arrives_back_in_chase() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._begin_reposition(Vector2(3, 0), 1.0)
	e._process_reposition(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_reposition_times_out() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._begin_reposition(Vector2(500, 0), 0.5)
	e._process_reposition(0.3)
	assert_int(e._state).is_equal(Enemy.State.REPOSITION)
	e._process_reposition(0.3)
	assert_int(e._state).is_equal(Enemy.State.CHASE)


func test_at_spot_in_range_attacks() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._has_spot = true
	e._spot_timer = 1.0
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_volley_end_forces_new_spot() -> void:
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._has_spot = true
	assert_int(e._state_after_attack()).is_equal(Enemy.State.RECOVER)
	assert_bool(e._has_spot).is_false()


func test_no_valid_spot_still_attacks() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	world.encounter_director.solid_check = func(_p: Vector2) -> bool: return true
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._world_manager = world
	e._director = null
	world.encounter_director.update(Vector2(120, 0), [e])
	e._process_chase(0.016)   # no spot found -> stays, requests token
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	world.encounter_director.update(Vector2(120, 0), [e])
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.WINDUP)


func test_spot_is_claimed_with_director() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e := _make(DropTable.EnemyTier.NORMAL)
	e._world_manager = world
	e._director = null
	e._process_chase(0.016)
	assert_int(world.encounter_director.get_taken_spots(null).size()).is_equal(1)


func test_claim_survives_director_prune() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e := _make(DropTable.EnemyTier.NORMAL)
	e.can_see = false
	e._world_manager = world
	e._director = null
	e._process_chase(0.016)   # claims a spot without seeing the player
	assert_bool(e.is_pursuing()).is_true()
	world.encounter_director.update(Vector2(120, 0), [e])
	assert_int(world.encounter_director.get_taken_spots(null).size()).is_equal(1)


func test_alert_still_fires_after_claiming() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e := _make(DropTable.EnemyTier.NORMAL)
	e.can_see = false
	e._world_manager = world
	e._director = null
	e._process_chase(0.016)   # claims a spot -> _aggroed is already true
	assert_bool(e._aggroed).is_true()
	var neighbour: Enemy = auto_free(Enemy.new())
	add_child(neighbour)
	neighbour.global_position = e.global_position + Vector2(50, 0)
	e.can_see = true
	e._process_chase(0.016)   # first sight: the alert must still go out
	assert_float(neighbour._alert_timer).is_greater_equal(0.0)


func test_reposition_steers_around_terrain() -> void:
	var e: TerrainRanged = auto_free(TerrainRanged.new())
	e.enemy_tier = DropTable.EnemyTier.NORMAL
	add_child(e)
	e.global_position = Vector2.ZERO
	e._begin_reposition(Vector2(100, 0), 1.0)
	e._process_reposition(0.016)
	assert_int(e._state).is_equal(Enemy.State.REPOSITION)
	assert_float(e.velocity.normalized().dot(Vector2(0, 1))).is_greater(0.99)


func test_facing_leads_moving_player() -> void:
	var e := _make(DropTable.EnemyTier.HARD)
	(e._player_ref as CharacterBody2D).velocity = Vector2(0, 100)
	var d := e.get_facing_direction()
	assert_float(d.y).is_greater(0.0)
