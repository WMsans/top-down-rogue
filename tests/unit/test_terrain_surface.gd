extends GdUnitTestSuite

class FakeAdapter:
	var place_gas_calls := []
	var place_lava_calls := []
	var read_result: PackedByteArray

	func place_gas(pos: Vector2, radius: float, density: int, velocity: Vector2i) -> void:
		place_gas_calls.append({"pos": pos, "radius": radius, "density": density})

	func place_lava(pos: Vector2, radius: float) -> void:
		place_lava_calls.append({"pos": pos, "radius": radius})

	func read_region(rect: Rect2i) -> PackedByteArray:
		return read_result

	func find_spawn_position(origin: Vector2i, body_size: Vector2i, max_radius: float) -> Vector2i:
		return Vector2i(100, 100)

	func get_active_chunk_coords() -> Array:
		return []


func test_place_gas_delegates_to_adapter() -> void:
	var fake := FakeAdapter.new()
	var surface := TerrainSurface.new()
	surface.adapter = fake
	surface.place_gas(Vector2(10, 20), 5.0, 200)
	assert_that(fake.place_gas_calls.size()).is_equal(1)
	assert_that(fake.place_gas_calls[0].density).is_equal(200)

func test_place_lava_delegates_to_adapter() -> void:
	var fake := FakeAdapter.new()
	var surface := TerrainSurface.new()
	surface.adapter = fake
	surface.place_lava(Vector2(30, 40), 8.0)
	assert_that(fake.place_lava_calls.size()).is_equal(1)

func test_null_adapter_does_not_crash() -> void:
	var surface := TerrainSurface.new()
	surface.place_gas(Vector2.ZERO, 1.0, 100)
	surface.place_lava(Vector2.ZERO, 1.0)
	assert_bool(true).is_true()
