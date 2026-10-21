extends GdUnitTestSuite

class TestBoss extends BossEnemy:
	func _ready() -> void:
		pass
	var transition_log: Array = []

	func _transition_phase() -> void:
		transition_log.append(current_phase)
		super._transition_phase()


func test_boss_phase_threshold_values() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.phase_count = 3
	assert_that(b._phase_threshold(2)).is_equal(20)
	assert_that(b._phase_threshold(3)).is_equal(10)

func test_phase_chaining_on_burst() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.current_phase = 1
	b.hits_remaining = 5
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(b.transition_log).is_equal([2, 3])

func test_take_hit_advances_phase() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.hits_remaining = 21
	b.current_phase = 1
	b.weapon = RangedWeapon.new()
	b.take_hit()
	assert_int(b.hits_remaining).is_equal(20)
	assert_that(b.current_phase).is_equal(2)

func test_status_tick_advances_phase() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.phase_count = 3
	b.max_hits = 30
	b.hits_remaining = 21
	b.current_phase = 1
	b.weapon = RangedWeapon.new()
	b.apply_status_damage(1)
	assert_that(b.current_phase).is_equal(2)

func test_phase_transition_clears_statuses() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	var sc: StatusComponent = auto_free(StatusComponent.new())
	b._status_component = sc
	sc.add_stain("on_fire", 5.0)
	b.weapon = RangedWeapon.new()
	b.current_phase = 2
	b._transition_phase()
	assert_float(sc.get_stain("on_fire")).is_equal(0.0)

func test_phase_2_sets_spread() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.weapon = RangedWeapon.new()
	b.weapon.projectile_count = 1
	b.weapon.spread_angle = 10.0
	b.current_phase = 2
	b._transition_phase()
	assert_that((b.weapon as RangedWeapon).projectile_count).is_equal(3)
	assert_that((b.weapon as RangedWeapon).spread_angle).is_equal(30.0)

func test_phase_3_sets_hazard_timer() -> void:
	var b: TestBoss = auto_free(TestBoss.new())
	b.hazard_interval = 5.0
	b.current_phase = 3
	b._transition_phase()
	assert_that(b._hazard_timer).is_equal(5.0)
