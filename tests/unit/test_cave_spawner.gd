extends GdUnitTestSuite

const _CaveSpawner = preload("res://src/core/cave_spawner.gd")
const _DummyEnemy = preload("res://scenes/enemies/dummy_enemy.tscn")

class _FakeWorldManager extends Node2D:
	var tracking_position: Vector2 = Vector2.ZERO
	func read_region(rect: Rect2i) -> PackedByteArray:
		var data := PackedByteArray()
		data.resize(rect.size.x * rect.size.y)
		data.fill(MaterialRegistry.MAT_AIR)
		return data


func test_mob_cap_enforcement() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.mob_cap = 3
	spawner.spawn_rate = 0.0  # ensure no random spawns can happen

	for _i in range(3):
		var enemy := _DummyEnemy.instantiate()
		enemy.add_to_group("cave_spawned")
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
	spawner._world_manager = auto_free(_FakeWorldManager.new())

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
	enemy.add_to_group("cave_spawned")
	add_child(enemy)
	enemy.global_position = Vector2(3000, 0)

	spawner._on_despawn_tick()

	assert_bool(enemy.is_queued_for_deletion()).is_true()


func test_despawn_keeps_nearby_enemy() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)

	spawner.despawn_dist = 2500.0

	var enemy := _DummyEnemy.instantiate()
	enemy.add_to_group("cave_spawned")
	add_child(enemy)
	enemy.global_position = Vector2(100, 0)

	spawner._on_despawn_tick()

	assert_bool(enemy.is_queued_for_deletion()).is_false()


func test_origin_density_mult_is_low_at_origin() -> void:
	assert_float(_CaveSpawner.origin_density_mult(0)).is_equal_approx(0.45, 0.001)

func test_origin_density_mult_is_full_at_wall() -> void:
	assert_float(_CaveSpawner.origin_density_mult(8)).is_equal_approx(1.0, 0.001)

func test_origin_density_mult_is_monotonic() -> void:
	var prev := -1.0
	for d in range(0, 9):
		var m := _CaveSpawner.origin_density_mult(d)
		assert_bool(m >= prev).is_true()
		prev = m


func test_density_mult_scales_validation_gate() -> void:
	var spawner := _CaveSpawner.new()
	add_child(spawner)
	spawner._world_manager = auto_free(_FakeWorldManager.new())
	spawner.spawn_min_dist = 0.0
	spawner.spawn_max_dist = 100000.0
	spawner.spawn_rate = 1.0  # gate = randf() > 0.5 * mult
	# Near origin: multiplier suppresses spawns hard.
	spawner._current_density_mult = 0.0
	var accepted := 0
	for _i in range(200):
		if spawner._validate_position(Vector2(500, 0)):
			accepted += 1
	assert_int(accepted).is_equal(0)


func test_mob_cap_default_is_trimmed() -> void:
	var spawner: _CaveSpawner = auto_free(_CaveSpawner.new())
	assert_int(spawner.mob_cap).is_equal(50)


func test_effective_elite_chance_scales_with_density() -> void:
	var spawner: _CaveSpawner = auto_free(_CaveSpawner.new())
	spawner.elite_chance = 0.4
	spawner._current_density_mult = 0.5
	assert_float(spawner._effective_elite_chance()).is_equal_approx(0.2, 0.001)
