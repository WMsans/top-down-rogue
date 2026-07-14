extends GdUnitTestSuite

class PatternBoss extends BossEnemy:
	var calls: Array = []
	func _ready() -> void:
		pass
	func _pattern_count(_phase: int) -> int:
		return 2
	func _execute_pattern(phase: int, index: int) -> void:
		calls.append(index)


class SingleBoss extends BossEnemy:
	func _ready() -> void:
		pass


func test_execute_attack_rotates_pattern_index() -> void:
	var b : PatternBoss = auto_free(PatternBoss.new())
	b.current_phase = 1
	b.encounter_active = true
	b._execute_attack()
	b._execute_attack()
	b._execute_attack()
	b._execute_attack()
	assert_that(b.calls).is_equal([0, 1, 0, 1])


func test_execute_attack_suppressed_when_encounter_inactive() -> void:
	var b : PatternBoss = auto_free(PatternBoss.new())
	b.current_phase = 1
	b.encounter_active = false
	b._execute_attack()
	b._execute_attack()
	assert_int(b.calls.size()).is_equal(0)


func test_pick_pattern_single_count_returns_zero() -> void:
	var b : SingleBoss = auto_free(SingleBoss.new())
	b._pattern_index = 5
	assert_int(b._pick_pattern(1)).is_equal(0)
	assert_int(b._pattern_index).is_equal(0)