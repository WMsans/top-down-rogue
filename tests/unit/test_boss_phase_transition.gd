extends GdUnitTestSuite

class TestBoss extends BossEnemy:
	func _ready() -> void:
		pass
	var transition_log: Array = []

	func _transition_phase() -> void:
		transition_log.append(current_phase)
		super._transition_phase()


func test_boss_phase_threshold_values() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.max_health = 300
	b.phase_count = 3
	assert_that(b._phase_threshold(2)).is_equal(200)
	assert_that(b._phase_threshold(3)).is_equal(100)

func test_phase_chaining_on_burst_damage() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 300
	b.current_phase = 1
	b.health = 50
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(b.transition_log).is_equal([2, 3])

func test_phase_2_sets_spread() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.weapon = RangedWeapon.new()
	b.weapon.projectile_count = 1
	b.weapon.spread_angle = 10.0
	b.current_phase = 2
	b._transition_phase()
	assert_that((b.weapon as RangedWeapon).projectile_count).is_equal(3)
	assert_that((b.weapon as RangedWeapon).spread_angle).is_equal(30.0)

func test_phase_3_sets_hazard_timer() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.hazard_interval = 5.0
	b.current_phase = 3
	b._transition_phase()
	assert_that(b._hazard_timer).is_equal(5.0)
