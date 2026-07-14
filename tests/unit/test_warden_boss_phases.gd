extends GdUnitTestSuite

const WardenScript := preload("res://src/enemies/bosses/warden_boss.gd")

class FakeWarden extends WardenScript:
	var fires: Array = []
	var forces: Array = []
	var minions: Array = []
	var props: Array = []
	func _ready() -> void:
		pass
	func _fire_ricochet(count: int) -> void:
		fires.append(count)
	func _apply_player_force(dir: Vector2, magnitude: float) -> void:
		forces.append({"dir": dir, "mag": magnitude})
	func _spawn_minion(scene: PackedScene, world_pos: Vector2, is_elite: bool) -> void:
		minions.append({"pos": world_pos, "elite": is_elite})
	func _spawn_prop(scene: PackedScene, world_pos: Vector2) -> void:
		props.append({"pos": world_pos})
	func _spawn_telegraph_shockwave(_c: Vector2, _r: float, _d: float) -> void:
		pass
	func _spawn_telegraph_converging(_t: Vector2, _r: float, _d: float, _c: Color) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b: FakeWarden = auto_free(FakeWarden.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_single_then_pair() -> void:
	var b: FakeWarden = auto_free(FakeWarden.new())
	b.current_phase = 1
	b._execute_pattern(1, 0)
	b._execute_pattern(1, 1)
	assert_that(b.fires).is_equal([1, 2])

func test_phase_3_a_summons_one_elite() -> void:
	var b: FakeWarden = auto_free(FakeWarden.new())
	b.current_phase = 3
	b._execute_pattern(3, 0)
	assert_int(b.minions.size()).is_equal(1)
	assert_bool(b.minions[0]["elite"]).is_true()

func test_phase_3_b_drops_gold_clusters() -> void:
	var b: FakeWarden = auto_free(FakeWarden.new())
	b.current_phase = 3
	b._execute_pattern(3, 1)
	assert_int(b.props.size()).is_greater_equal(3)
