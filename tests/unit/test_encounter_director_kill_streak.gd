extends GdUnitTestSuite


func test_kill_streak_starts_at_zero() -> void:
	var dir := EncounterDirector.new()
	assert_int(dir.kill_streak).is_equal(0)


func test_register_kill_increments_by_two() -> void:
	var dir := EncounterDirector.new()
	dir.register_kill()
	assert_int(dir.kill_streak).is_equal(2)


func test_register_kill_clamps_at_max() -> void:
	var dir := EncounterDirector.new()
	for _i in range(10):
		dir.register_kill()
	assert_int(dir.kill_streak).is_equal(4)


func test_register_player_hit_decrements_by_one() -> void:
	var dir := EncounterDirector.new()
	dir.register_kill()
	dir.register_kill()
	dir.register_player_hit()
	assert_int(dir.kill_streak).is_equal(3)


func test_register_player_hit_clamps_at_min() -> void:
	var dir := EncounterDirector.new()
	for _i in range(10):
		dir.register_player_hit()
	assert_int(dir.kill_streak).is_equal(-2)
