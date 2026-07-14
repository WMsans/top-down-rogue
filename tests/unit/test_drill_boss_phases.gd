extends GdUnitTestSuite

const DrillScript := preload("res://src/enemies/bosses/drill_boss.gd")

class FakeDrill extends DrillScript:
	var props: Array = []
	var stones: Array = []
	var charges: Array = []
	func _ready() -> void:
		pass
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"scene": scene, "pos": world_pos})
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stones.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _do_straight_bore(_target: Vector2) -> void:
		charges.append("straight")
	func _do_double_bore(_target: Vector2) -> void:
		charges.append("double")
	func _spawn_telegraph_ground_crack(_s: Vector2, _e: Vector2, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b: FakeDrill = auto_free(FakeDrill.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_straight_then_double() -> void:
	var b: FakeDrill = auto_free(FakeDrill.new())
	b.current_phase = 1
	b._set_player_pos_for_test(Vector2(80, 0))
	b.global_position = Vector2.ZERO
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_that(b.charges).is_equal(["straight", "double"])

func test_phase_2_a_scatters_four_mines() -> void:
	var b: FakeDrill = auto_free(FakeDrill.new())
	b.current_phase = 2
	b._execute_pattern(2, 0)
	assert_int(b.props.size()).is_equal(4)

func test_phase_3_a_stamps_stone_pillars() -> void:
	var b: FakeDrill = auto_free(FakeDrill.new())
	b.current_phase = 3
	b._execute_pattern(3, 0)
	assert_int(b.stones.size()).is_greater_equal(1)
	assert_int(b.stones[0]["mat"]).is_equal(MaterialRegistry.MAT_STONE)
