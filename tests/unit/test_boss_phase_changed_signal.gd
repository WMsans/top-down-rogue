extends GdUnitTestSuite

class EnterBoss extends BossEnemy:
	var entered: Array = []
	func _ready() -> void:
		pass
	func _on_phase_enter(phase: int) -> void:
		entered.append(phase)


func test_phase_changed_emits_on_each_transition() -> void:
	var b : EnterBoss = auto_free(EnterBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 300
	b.current_phase = 1
	var phases: Array = []
	b.phase_changed.connect(func(p): phases.append(p))
	b.health = 50
	b._check_phase_transition()
	assert_that(b.current_phase).is_equal(3)
	assert_that(phases).is_equal([2, 3])


func test_on_phase_enter_called_after_state_set() -> void:
	var b : EnterBoss = auto_free(EnterBoss.new())
	b.max_health = 300
	b.phase_count = 3
	b.health = 200
	b.current_phase = 1
	b.health = 100
	b._check_phase_transition()
	assert_that(b.entered).is_equal([2, 3])