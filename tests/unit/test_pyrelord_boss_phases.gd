extends GdUnitTestSuite

const PyrelordScript := preload("res://src/enemies/bosses/pyrelord_boss.gd")

class FakePyrelord extends PyrelordScript:
	var stamps: Array = []
	var rings: Array = []
	var fires: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _stamp_material_ring(pos: Vector2, inner: float, outer: float, mat_id: int) -> void:
		rings.append({"pos": pos, "inner": inner, "outer": outer, "mat": mat_id})
	func _fire_pattern(projectile_count: int, spread: float) -> void:
		fires.append({"count": projectile_count, "spread": spread})
	func _ring_pattern(index: int) -> void:
		if index == 0:
			_stamp_material_ring(_center, 80.0, 110.0, MaterialRegistry.MAT_LAVA)
		else:
			_stamp_material_ring(_center, 40.0, 160.0, MaterialRegistry.MAT_LAVA)
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b: FakePyrelord = auto_free(FakePyrelord.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_spread() -> void:
	var b: FakePyrelord = auto_free(FakePyrelord.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_int(b.fires.size()).is_equal(2)
	assert_int(b.fires[0]["count"]).is_equal(1)
	assert_int(b.fires[1]["count"]).is_equal(3)
	assert_float(b.fires[1]["spread"]).is_equal(30.0)

func test_phase_3_a_stamps_lava_ring() -> void:
	var b: FakePyrelord = auto_free(FakePyrelord.new())
	b.current_phase = 3
	b._set_center_for_test(Vector2.ZERO)
	b._execute_pattern(3, 0)
	assert_int(b.rings.size()).is_greater_equal(1)
	assert_int(b.rings[0]["mat"]).is_equal(MaterialRegistry.MAT_LAVA)
