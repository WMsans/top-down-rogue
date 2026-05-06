extends GdUnitTestSuite

const TEST_LIGHT_RANGE := 100.0


func test_register_and_unregister_entity() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)

	fow.register(entity)
	assert_that(fow._entities.size()).is_equal(1)
	assert_that(fow._entity_ids.size()).is_equal(1)

	fow.unregister(entity)
	assert_that(fow._entities.size()).is_equal(0)
	assert_that(fow._entity_ids.size()).is_equal(0)


func test_register_duplicate_ignored() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)

	fow.register(entity)
	fow.register(entity)
	assert_that(fow._entities.size()).is_equal(1)
	assert_that(fow._entity_ids.size()).is_equal(1)


func test_register_player_light() -> void:
	var fow := autofree(FogOfWar.new())
	var light := autofree(Node2D.new())
	add_child(light)

	fow.register_player_light(light, 128.0)
	assert_that(fow._player_lights.size()).is_equal(1)
	assert_that(fow._player_lights[0].range).is_equal(128.0)

	# update existing light
	fow.register_player_light(light, 200.0)
	assert_that(fow._player_lights.size()).is_equal(1)
	assert_that(fow._player_lights[0].range).is_equal(200.0)


func test_register_chunk_lights() -> void:
	var fow := autofree(FogOfWar.new())
	var cl := autofree(Node2D.new())
	add_child(cl)

	fow.register_chunk_lights(cl)
	assert_that(fow._chunk_lights_nodes.size()).is_equal(1)

	fow.unregister_chunk_lights(cl)
	assert_that(fow._chunk_lights_nodes.size()).is_equal(0)


func test_collect_active_lights_player_only() -> void:
	var fow := autofree(FogOfWar.new())
	var light := autofree(Node2D.new())
	add_child(light)
	light.position = Vector2(50, 50)

	fow.register_player_light(light, 128.0)
	var active := fow._collect_active_lights()
	assert_that(active.size()).is_equal(1)
	assert_that(active[0].range).is_equal(128.0)


func test_compute_visibility_no_lights_returns_zero() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)
	entity.position = Vector2(100, 100)

	var vis := fow._compute_visibility(entity, {})
	assert_that(vis).is_equal(0.0)


func test_compute_visibility_entity_at_light_center_returns_one() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)
	entity.position = Vector2(100, 100)

	var light_data := {
		position = Vector2(100, 100),
		range = TEST_LIGHT_RANGE,
	}
	var buckets := {Vector2i(0, 0): [light_data]}

	var vis := fow._compute_visibility(entity, buckets)
	assert_that(vis).is_equal(1.0)


func test_compute_visibility_entity_at_half_range() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)
	entity.position = Vector2(100, 100)

	var light_data := {
		position = Vector2(150, 100),  # 50px away, half of 100 range
		range = TEST_LIGHT_RANGE,
	}
	var buckets := {Vector2i(0, 0): [light_data]}

	var vis := fow._compute_visibility(entity, buckets)
	assert_that(vis).is_equal(0.5)


func test_compute_visibility_entity_beyond_range() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)
	entity.position = Vector2(100, 100)

	var light_data := {
		position = Vector2(300, 100),  # 200px away, beyond 100*1.2 buffer
		range = TEST_LIGHT_RANGE,
	}
	var buckets := {Vector2i(0, 0): [light_data]}

	var vis := fow._compute_visibility(entity, buckets)
	assert_that(vis).is_equal(0.0)


func test_bucket_lights_places_light_in_correct_cells() -> void:
	var fow := autofree(FogOfWar.new())
	var lights: Array[Dictionary] = [{
		position = Vector2(100, 100),
		range = 50.0,
	}]
	var buckets := fow._bucket_lights(lights)
	assert_that(buckets.size()).is_greater(0)


func test_cache_same_position_returns_cached_value() -> void:
	var fow := autofree(FogOfWar.new())
	var entity := autofree(Node2D.new())
	add_child(entity)
	entity.position = Vector2(100, 100)
	fow.register(entity)

	var light_data := {
		position = Vector2(100, 100),
		range = TEST_LIGHT_RANGE,
	}
	var buckets := {Vector2i(0, 0): [light_data]}

	var vis1 := fow._compute_visibility(entity, buckets)
	# Without moving entity, should return cached value
	var vis2 := fow._compute_visibility(entity, buckets)
	assert_that(vis1).is_equal(vis2)
