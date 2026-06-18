extends GdUnitTestSuite

const SpawnDispatcher = preload("res://src/core/spawn_dispatcher.gd")

func test_roll_melee_is_lunge_boundaries() -> void:
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.0)).is_true()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.24)).is_true()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.25)).is_false()
	assert_bool(SpawnDispatcher.roll_melee_is_lunge(0.9)).is_false()

func test_lunge_chance_keeps_default_melee_majority() -> void:
	assert_float(SpawnDispatcher.LUNGE_MELEE_CHANCE).is_less(0.5)
