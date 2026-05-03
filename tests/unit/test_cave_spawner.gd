extends GdUnitTestSuite

const _CaveSpawner = preload("res://src/core/cave_spawner.gd")
const _DummyEnemy = preload("res://scenes/dummy_enemy.tscn")


func test_mob_cap_enforcement() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.mob_cap = 3
	spawner.spawn_rate = 0.0  # ensure no random spawns can happen

	for _i in range(3):
		var enemy := _DummyEnemy.instantiate()
		add_child(enemy)

	spawner._on_spawn_tick()

	var live := spawner._count_live_enemies()
	assert_that(live).is_equal(3)


func test_distance_validation_rejects_too_close() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0

	assert_bool(spawner._validate_position(Vector2(100, 0))).is_false()


func test_distance_validation_rejects_too_far() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0

	assert_bool(spawner._validate_position(Vector2(3000, 0))).is_false()


func test_distance_validation_accepts_in_range() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 600.0
	spawner.spawn_max_dist = 2000.0
	spawner.spawn_rate = 2.0

	assert_bool(spawner._validate_position(Vector2(1000, 0))).is_true()


func test_spawn_rate_zero_always_rejects() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.spawn_min_dist = 0.0
	spawner.spawn_max_dist = 100000.0
	spawner.spawn_rate = 0.0

	var accepted := false
	for _i in range(100):
		if spawner._validate_position(Vector2(randi() % 2000, randi() % 2000)):
			accepted = true
			break

	assert_bool(accepted).is_false()


func test_despawn_removes_far_enemy() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.despawn_dist = 2500.0

	var enemy := _DummyEnemy.instantiate()
	add_child(enemy)
	enemy.global_position = Vector2(3000, 0)

	spawner._on_despawn_tick()

	assert_bool(enemy.is_queued_for_deletion()).is_true()


func test_despawn_keeps_nearby_enemy() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.despawn_dist = 2500.0

	var enemy := _DummyEnemy.instantiate()
	add_child(enemy)
	enemy.global_position = Vector2(100, 0)

	spawner._on_despawn_tick()

	assert_bool(enemy.is_queued_for_deletion()).is_false()
