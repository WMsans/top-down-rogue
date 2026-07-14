extends GdUnitTestSuite

const GlacierScript := preload("res://src/enemies/bosses/glacier_boss.gd")

class FakeGlacier extends GlacierScript:
	var stamps: Array = []
	var rings: Array = []
	var fires: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _fire_shards(count: int, burst: int) -> void:
		fires.append({"count": count, "burst": burst})
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass
	func _spawn_telegraph_column(_b: Vector2, _h: float, _d: float) -> void:
		pass
	func _chill_pattern(index: int) -> void:
		if index == 0:
			_stamp_material(Vector2(50, 0), PILLAR_RADIUS, MaterialRegistry.MAT_ICE)
		else:
			_stamp_material_ring(global_position, RING_RADIUS - 16.0, RING_RADIUS, MaterialRegistry.MAT_ICE)
	func _pillar_pattern(index: int) -> void:
		if index == 1:
			var center := _player_pos()
			var gap := randi() % 8
			for i in 8:
				if i == gap:
					continue
				var a := float(i) / 8.0 * TAU
				var pos := center + Vector2(cos(a), sin(a)) * RING_RADIUS
				_stamp_material(pos, PILLAR_RADIUS, MaterialRegistry.MAT_ICE)

func test_pattern_count_two_per_phase() -> void:
	var b: FakeGlacier = auto_free(FakeGlacier.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_volley() -> void:
	var b: FakeGlacier = auto_free(FakeGlacier.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_int(b.fires[0]["count"]).is_equal(1)
	assert_int(b.fires[1]["count"]).is_equal(3)
	assert_int(b.fires[1]["burst"]).is_equal(3)

func test_phase_2_a_stamps_ice_disc() -> void:
	var b: FakeGlacier = auto_free(FakeGlacier.new())
	b.current_phase = 2
	b._set_player_pos_for_test(Vector2(50, 0))
	b.global_position = Vector2.ZERO
	b._execute_pattern(2, 0)
	assert_int(b.stamps.size()).is_greater_equal(1)
	assert_int(b.stamps[0]["mat"]).is_equal(MaterialRegistry.MAT_ICE)

func test_phase_3_b_stamps_pillar_ring_with_gap() -> void:
	var b: FakeGlacier = auto_free(FakeGlacier.new())
	b.current_phase = 3
	b._set_player_pos_for_test(Vector2.ZERO)
	b._execute_pattern(3, 1)
	assert_int(b.stamps.size()).is_equal(7)
