extends GdUnitTestSuite

const BurrowerScript := preload("res://src/enemies/bosses/burrower_boss.gd")

class FakeBurrower extends BurrowerScript:
	var stamps: Array = []
	var navigations: Array = []
	var charges: Array = []
	var dust_bursts: Array = []
	func _ready() -> void:
		pass
	func _stamp_material(pos: Vector2, radius: float, mat_id: int) -> void:
		stamps.append({"pos": pos, "radius": radius, "mat": mat_id})
	func _lock_navigation(locked: bool) -> void:
		navigations.append(locked)
	func _do_directed_charge() -> void:
		charges.append("directed")
	func _do_sweep_charge() -> void:
		charges.append("sweep")
	func _do_dust_burst_after_charge() -> void:
		dust_bursts.append("after")
	func _spawn_telegraph_ground_crack(_s: Vector2, _e: Vector2, _d: float) -> void:
		pass
	func _spawn_telegraph_expanding(_c: Vector2, _r: float, _d: float) -> void:
		pass

func test_pattern_count_two_per_phase() -> void:
	var b: FakeBurrower = auto_free(FakeBurrower.new())
	for p in [1, 2, 3]:
		assert_int(b._pattern_count(p)).is_equal(2)

func test_phase_1_rotates_directed_then_sweep() -> void:
	var b: FakeBurrower = auto_free(FakeBurrower.new())
	b.current_phase = 1
	b.max_health = 100; b.health = 100
	b.encounter_active = true
	for i in 2:
		b._execute_pattern(1, i)
	assert_that(b.charges).is_equal(["directed", "sweep"])

func test_phase_3_hazard_interval_stamps_pit() -> void:
	var b: FakeBurrower = auto_free(FakeBurrower.new())
	b.hazard_interval = 0.5
	b.current_phase = 3
	b._on_phase_enter(3)
	b._tick_phase(0.5)
	assert_int(b.stamps.size()).is_greater_equal(1)
	var first: Dictionary = b.stamps[0]
	assert_int(first["mat"]).is_equal(MaterialRegistry.MAT_AIR)

func _new_boss() -> FakeBurrower:
	var b: FakeBurrower = auto_free(FakeBurrower.new())
	b.max_health = 100; b.health = 100
	return b
