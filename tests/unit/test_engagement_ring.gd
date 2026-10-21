extends GdUnitTestSuite

class Agent extends Node2D:
	var pursuing: bool = true
	var enemy_tier: int = DropTable.EnemyTier.EASY
	var is_elite: bool = false
	func is_pursuing() -> bool:
		return pursuing

class FakeWorld extends Node:
	var swarm_grid = preload("res://src/core/swarm_grid.gd").new(32.0)
	var encounter_director := EncounterDirector.new()
	var nav_field = null

class MockEnemy extends Enemy:
	func _execute_attack() -> void:
		pass
	func _can_see_player() -> bool:
		return true


func _agent(pos: Vector2) -> Agent:
	var a: Agent = auto_free(Agent.new())
	add_child(a)
	a.global_position = pos
	return a


func _ring_of(d: EncounterDirector, positions: Array) -> Array:
	var agents: Array = []
	for p in positions:
		agents.append(_agent(p))
	d.update(Vector2.ZERO, agents, 0.0, Vector2.RIGHT)
	for a in agents:
		d.join_ring(a, 50.0)
	return agents


func test_slots_are_distinct_and_on_radius() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2(0, 40)])
	var s0 := d.get_slot(agents[0])
	var s1 := d.get_slot(agents[1])
	assert_bool(s0.is_equal_approx(s1)).is_false()
	assert_float(s0.length()).is_equal_approx(50.0, 0.01)
	assert_float(s1.length()).is_equal_approx(50.0, 0.01)


func test_three_members_put_one_behind_player() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2.from_angle(2.0) * 40.0, Vector2.from_angle(-2.0) * 40.0])
	var behind := false
	for a in agents:
		if d.get_slot(a).is_equal_approx(Vector2(-50, 0)):
			behind = true
	assert_bool(behind).is_true()


func test_solid_slot_rotates_to_open_angle() -> void:
	var d := EncounterDirector.new()
	d.solid_check = func(p: Vector2) -> bool: return p.x < -1.0
	var agents := _ring_of(d, [Vector2(-40, 0)])
	var s := d.get_slot(agents[0])
	assert_bool(s == Vector2.INF).is_false()
	assert_float(s.x).is_greater_equal(-1.0)


func test_all_solid_returns_inf() -> void:
	var d := EncounterDirector.new()
	d.solid_check = func(_p: Vector2) -> bool: return true
	var agents := _ring_of(d, [Vector2(40, 0)])
	assert_that(d.get_slot(agents[0])).is_equal(Vector2.INF)


func test_leave_ring_and_prune() -> void:
	var d := EncounterDirector.new()
	var agents := _ring_of(d, [Vector2(40, 0), Vector2(0, 40)])
	d.leave_ring(agents[0])
	assert_that(d.get_slot(agents[0])).is_equal(Vector2.INF)
	agents[1].pursuing = false
	d.update(Vector2.ZERO, agents)
	assert_that(d.get_slot(agents[1])).is_equal(Vector2.INF)


func test_enemy_without_token_moves_to_ring_at_normal_speed() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 28.0
	e.speed = 60.0
	e.global_position = Vector2(20, 0)
	e._state = Enemy.State.CHASE
	world.encounter_director.update(Vector2.ZERO, [e], 0.0, Vector2.RIGHT)
	# Fill the pool (NORMAL band = 6) so this enemy cannot get a token.
	for i in range(6):
		var blocker := _agent(Vector2(-100 - i, 0))
		world.encounter_director._tokens[blocker] = {"cost": 1.0, "age": 0.0, "attacking": true}
	e._process_chase(0.016)
	assert_int(e._state).is_equal(Enemy.State.CHASE)
	assert_that(world.encounter_director.get_slot(e)).is_not_equal(Vector2.INF)
	assert_float(e.velocity.length()).is_equal_approx(60.0, 0.5)


func test_enemy_leaves_ring_on_windup() -> void:
	var world: FakeWorld = auto_free(FakeWorld.new())
	add_child(world)
	var e: MockEnemy = auto_free(MockEnemy.new())
	add_child(e)
	e._world_manager = world
	e._director = null
	var p: Node2D = auto_free(Node2D.new())
	add_child(p)
	e._player_ref = p
	e._player_in_range = true
	e._attack_range = 28.0
	e.global_position = Vector2(20, 0)
	e._state = Enemy.State.CHASE
	world.encounter_director.update(Vector2.ZERO, [e])
	e._process_chase(0.016)   # joins ring, requests
	world.encounter_director.update(Vector2.ZERO, [e])
	e._process_chase(0.016)   # has token, in range
	assert_int(e._state).is_equal(Enemy.State.WINDUP)
	assert_that(world.encounter_director.get_slot(e)).is_equal(Vector2.INF)
