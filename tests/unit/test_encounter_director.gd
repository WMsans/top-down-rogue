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
