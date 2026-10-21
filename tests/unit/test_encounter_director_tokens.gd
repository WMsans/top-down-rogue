extends GdUnitTestSuite

class Agent extends Node2D:
	var pursuing: bool = true
	var enemy_tier: int = DropTable.EnemyTier.EASY
	var is_elite: bool = false
	var cost: float = 1.0
	func is_pursuing() -> bool:
		return pursuing
	func token_cost() -> float:
		return cost


func _agent(pos: Vector2, tier: int = DropTable.EnemyTier.EASY) -> Agent:
	var a: Agent = auto_free(Agent.new())
	a.enemy_tier = tier
	add_child(a)
	a.global_position = pos
	return a


func test_capacity_easy_band_is_four() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [_agent(Vector2(10, 0))])
	assert_float(d.max_tokens()).is_equal(4.0)


func test_capacity_deep_band_is_six() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [_agent(Vector2(10, 0)), _agent(Vector2(20, 0), DropTable.EnemyTier.NORMAL)])
	assert_float(d.max_tokens()).is_equal(6.0)


func test_capacity_plus_one_per_elite() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	var b := _agent(Vector2(20, 0))
	a.is_elite = true
	b.is_elite = true
	d.update(Vector2.ZERO, [a, b])
	assert_float(d.max_tokens()).is_equal(6.0)


func test_grant_happens_on_update() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	assert_bool(d.request_token(a)).is_false()
	d.update(Vector2.ZERO, [a])
	assert_bool(d.has_token(a)).is_true()
	assert_bool(d.request_token(a)).is_true()


func test_pool_caps_grants() -> void:
	var d := EncounterDirector.new()
	var agents: Array = []
	for i in range(5):
		agents.append(_agent(Vector2(-10 - i, 0)))
	d.update(Vector2.ZERO, agents)
	for a in agents:
		d.request_token(a)
	d.update(Vector2.ZERO, agents)
	assert_float(d.used_tokens()).is_equal(4.0)


func test_ranged_costs_half() -> void:
	var d := EncounterDirector.new()
	var agents: Array = []
	for i in range(8):
		var a := _agent(Vector2(-10 - i, 0))
		a.cost = 0.5
		agents.append(a)
	d.update(Vector2.ZERO, agents)
	for a in agents:
		d.request_token(a)
	d.update(Vector2.ZERO, agents)
	for a in agents:
		assert_bool(d.has_token(a)).is_true()


func test_aim_cone_requests_lose_to_flankers() -> void:
	var d := EncounterDirector.new()
	# Facing RIGHT. One agent sits in the cone and is closest; four flank.
	var front := _agent(Vector2(5, 0))
	var flankers: Array = [_agent(Vector2(-20, 0)), _agent(Vector2(0, 20)), _agent(Vector2(0, -20)), _agent(Vector2(-20, 5))]
	var all: Array = flankers.duplicate()
	all.append(front)
	d.update(Vector2.ZERO, all, 0.0, Vector2.RIGHT)
	d.request_token(front)
	for f in flankers:
		d.request_token(f)
	d.update(Vector2.ZERO, all, 0.0, Vector2.RIGHT)
	assert_bool(d.has_token(front)).is_false()
	for f in flankers:
		assert_bool(d.has_token(f)).is_true()


func test_release_frees_capacity() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.release_token(a)
	assert_bool(d.has_token(a)).is_false()
	assert_float(d.used_tokens()).is_equal(0.0)


func test_token_times_out_without_attacking() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.update(Vector2.ZERO, [a], 1.5)
	assert_bool(d.has_token(a)).is_true()
	d.update(Vector2.ZERO, [a], 1.5)
	assert_bool(d.has_token(a)).is_false()


func test_attacking_token_does_not_time_out() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.mark_attacking(a)
	d.update(Vector2.ZERO, [a], 5.0)
	assert_bool(d.has_token(a)).is_true()


func test_non_pursuing_holder_is_pruned() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	a.pursuing = false
	d.update(Vector2.ZERO, [a])
	assert_bool(d.has_token(a)).is_false()


func test_freed_holder_is_pruned() -> void:
	var d := EncounterDirector.new()
	var a: Agent = Agent.new()
	add_child(a)
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	a.free()
	d.update(Vector2.ZERO, [])
	assert_float(d.used_tokens()).is_equal(0.0)


func test_unregister_releases_token() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(a)
	d.update(Vector2.ZERO, [a])
	d.unregister(a)
	assert_bool(d.has_token(a)).is_false()


func test_facing_polls_every_two_seconds() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [], 0.0, Vector2.RIGHT)
	assert_that(d.get_player_facing()).is_equal(Vector2.RIGHT)
	d.update(Vector2.ZERO, [], 1.0, Vector2.LEFT)
	assert_that(d.get_player_facing()).is_equal(Vector2.RIGHT)
	d.update(Vector2.ZERO, [], 1.0, Vector2.LEFT)
	assert_that(d.get_player_facing()).is_equal(Vector2.LEFT)


func test_zero_facing_keeps_last_value() -> void:
	var d := EncounterDirector.new()
	d.update(Vector2.ZERO, [], 0.0, Vector2.UP)
	d.update(Vector2.ZERO, [], 2.0, Vector2.ZERO)
	assert_that(d.get_player_facing()).is_equal(Vector2.UP)


func test_token_granted_only_to_active_requester() -> void:
	var d := EncounterDirector.new()
	var a := _agent(Vector2(10, 0))
	var b := _agent(Vector2(20, 0))
	d.update(Vector2.ZERO, [a])
	d.request_token(b)
	d.update(Vector2.ZERO, [a])
	assert_bool(d.has_token(b)).is_false()
