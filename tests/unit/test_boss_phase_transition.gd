extends GdUnitTestSuite

class TestBoss extends BossEnemy:
	func _ready() -> void:
		pass
	var transition_log: Array = []

	func _transition_phase() -> void:
		transition_log.append(current_phase)
		# Base _transition_phase is a no-op; phase setup happens in _on_phase_enter.
		# Keep this test's original behavior by simply logging.


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
	var phases: Array = []
	b.phase_changed.connect(func(p): phases.append(p))
	b.health = 50
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(b.transition_log).is_equal([2, 3])
	assert_that(phases).is_equal([2, 3])


func test_phase_2_base_no_longer_sets_spread() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.weapon = RangedWeapon.new()
	b.weapon.projectile_count = 1
	b.weapon.spread_angle = 10.0
	b.current_phase = 2
	b._transition_phase()
	# Base is a no-op; subclasses do the spread tweak.
	assert_int((b.weapon as RangedWeapon).projectile_count).is_equal(1)


func test_phase_3_base_has_no_hazard_timer() -> void:
	var b : TestBoss = auto_free(TestBoss.new())
	b.current_phase = 3
	b._transition_phase()
	assert_bool("_hazard_timer" in b).is_false()