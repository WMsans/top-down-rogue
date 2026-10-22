extends GdUnitTestSuite


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	return r


func test_spot_is_inside_distance_band() -> void:
	for i in range(20):
		var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), _rng())
		assert_float(s.length()).is_between(100.0, 150.0)


func test_spot_biased_to_enemy_side() -> void:
	var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), _rng())
	assert_float(s.x).is_greater(0.0)


func test_spot_respects_spacing() -> void:
	var rng := _rng()
	var first := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), Callable(), rng)
	var second := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [first], Callable(), Callable(), rng)
	assert_float(first.distance_to(second)).is_greater_equal(40.0)


func test_solid_candidates_rejected() -> void:
	var solid := func(p: Vector2) -> bool: return p.y > 0.0
	var s := FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], solid, Callable(), _rng())
	assert_float(s.y).is_less_equal(0.0)


func test_no_valid_candidate_returns_inf() -> void:
	var solid := func(_p: Vector2) -> bool: return true
	assert_that(FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], solid, Callable(), _rng())).is_equal(Vector2.INF)


func test_angle_jitter_is_a_named_constant() -> void:
	assert_float(FiringSpotPicker.ANGLE_JITTER).is_equal(0.1)


func test_blocked_sight_returns_inf() -> void:
	var los := func(_a: Vector2, _b: Vector2) -> bool: return false
	assert_that(FiringSpotPicker.pick(Vector2(200, 0), Vector2.ZERO, [], Callable(), los, _rng())).is_equal(Vector2.INF)
