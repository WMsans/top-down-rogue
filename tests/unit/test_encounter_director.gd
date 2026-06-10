extends GdUnitTestSuite

const Director = preload("res://src/core/encounter_director.gd")

func _enemy_at(parent: Node, pos: Vector2) -> Node2D:
	var n: Node2D = auto_free(Node2D.new())
	parent.add_child(n)
	n.global_position = pos
	return n

func test_melee_pool_grants_up_to_count_then_denies() -> void:
	var d = Director.new()
	d.melee_token_count = 2
	var a := _enemy_at(self, Vector2(0, 0))
	var b := _enemy_at(self, Vector2(10, 0))
	var c := _enemy_at(self, Vector2(20, 0))
	d._active = [a, b, c]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_true()
	assert_bool(d.try_claim_attack(c, false)).is_false()

func test_release_frees_a_melee_slot() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _enemy_at(self, Vector2(0, 0))
	var b := _enemy_at(self, Vector2(10, 0))
	d._active = [a, b]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_false()
	d.release_attack(a)
	assert_bool(d.try_claim_attack(b, false)).is_true()

func test_melee_and_ranged_pools_are_independent() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	d.ranged_token_count = 1
	var m := _enemy_at(self, Vector2(0, 0))
	var r := _enemy_at(self, Vector2(10, 0))
	d._active = [m, r]
	assert_bool(d.try_claim_attack(m, false)).is_true()
	assert_bool(d.try_claim_attack(r, true)).is_true()

func test_claim_denied_when_not_active() -> void:
	var d = Director.new()
	d.melee_token_count = 2
	var a := _enemy_at(self, Vector2(0, 0))
	d._active = []
	assert_bool(d.try_claim_attack(a, false)).is_false()

func test_claim_is_idempotent_for_holder() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _enemy_at(self, Vector2(0, 0))
	d._active = [a]
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(a, false)).is_true()

func test_tokens_for_floor_scales_gently() -> void:
	assert_int(Director.tokens_for_floor(2, 1)).is_equal(2)
	assert_int(Director.tokens_for_floor(2, 3)).is_equal(2)
	assert_int(Director.tokens_for_floor(2, 4)).is_equal(3)
	assert_int(Director.tokens_for_floor(2, 9)).is_equal(3)

func test_catch_up_returns_base_when_close() -> void:
	var s := Director.catch_up_speed(60.0, 40.0, 120.0)
	assert_float(s).is_equal_approx(60.0, 0.001)

func test_catch_up_ramps_toward_cap_when_far() -> void:
	var s := Director.catch_up_speed(60.0, 1000.0, 120.0)
	assert_float(s).is_equal_approx(114.0, 0.001)

func test_catch_up_never_exceeds_player_cap() -> void:
	for dist in [0.0, 90.0, 300.0, 5000.0]:
		var s := Director.catch_up_speed(200.0, dist, 120.0)
		assert_float(s).is_less_equal(114.0 + 0.001)

class _PursuerStub extends Node2D:
	var pursuing: bool = false
	func is_pursuing() -> bool:
		return pursuing

func _stub_at(parent: Node, pos: Vector2, pursuing: bool) -> _PursuerStub:
	var n: _PursuerStub = auto_free(_PursuerStub.new())
	parent.add_child(n)
	n.global_position = pos
	n.pursuing = pursuing
	return n

func test_contagion_true_for_close_aggroed_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var aggro := _stub_at(self, Vector2(30, 0), true)
	var spread := Director.should_aggro_from_neighbors(me, [me, aggro])
	assert_bool(spread).is_true()

func test_contagion_false_for_far_aggroed_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var aggro := _stub_at(self, Vector2(100, 0), true)
	var spread := Director.should_aggro_from_neighbors(me, [me, aggro])
	assert_bool(spread).is_false()

func test_contagion_false_for_close_idle_neighbor() -> void:
	var me := _stub_at(self, Vector2(0, 0), false)
	var idle := _stub_at(self, Vector2(20, 0), false)
	var spread := Director.should_aggro_from_neighbors(me, [me, idle])
	assert_bool(spread).is_false()

func test_update_admits_only_pursuing_enemies() -> void:
	var d = Director.new()
	var a := _stub_at(self, Vector2(40, 0), true)
	var b := _stub_at(self, Vector2(0, 40), false)
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.is_active(a)).is_true()
	assert_bool(d.is_active(b)).is_false()

func test_update_enforces_soft_cap() -> void:
	var d = Director.new()
	var list: Array = []
	for i in range(Director.HORDE_SOFT_CAP + 5):
		list.append(_stub_at(self, Vector2(i * 20, 0), true))
	d.update(Vector2.ZERO, list)
	assert_int(d._active.size()).is_equal(Director.HORDE_SOFT_CAP)

func test_update_prunes_dead_holder_and_frees_token() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _PursuerStub.new()
	add_child(a)
	a.global_position = Vector2(40, 0)
	a.pursuing = true
	var b := _stub_at(self, Vector2(0, 40), true)
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.try_claim_attack(a, false)).is_true()
	assert_bool(d.try_claim_attack(b, false)).is_false()
	a.free()
	d.update(Vector2.ZERO, [b])
	assert_bool(d.try_claim_attack(b, false)).is_true()

func test_unregister_releases_membership_and_token() -> void:
	var d = Director.new()
	d.melee_token_count = 1
	var a := _stub_at(self, Vector2(40, 0), true)
	var b := _stub_at(self, Vector2(0, 40), true)
	d.update(Vector2.ZERO, [a, b])
	assert_bool(d.try_claim_attack(a, false)).is_true()
	d.unregister(a)
	assert_bool(d.is_active(a)).is_false()
	assert_bool(d.try_claim_attack(b, false)).is_true()
