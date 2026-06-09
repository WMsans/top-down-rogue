extends GdUnitTestSuite

const _SpawnValidation = preload("res://src/core/spawn_validation.gd")

# Stub world_manager: read_region fills the requested rect from a solid-cell set.
# Air cells use MAT_AIR; solid cells use a guaranteed-different byte.
class StubWM extends RefCounted:
	var solid_cells: Dictionary = {}      # Vector2i -> true
	var force_wrong_size: bool = false
	var force_oob_byte: int = -1          # if >=0, fill entire region with this byte

	func read_region(rect: Rect2i) -> PackedByteArray:
		var air := MaterialRegistry.MAT_AIR
		var solid := (air + 1) % 256
		var data := PackedByteArray()
		var count := rect.size.x * rect.size.y
		if force_wrong_size:
			data.resize(count - 1)
			data.fill(air)
			return data
		data.resize(count)
		for y in range(rect.size.y):
			for x in range(rect.size.x):
				var cell := Vector2i(rect.position.x + x, rect.position.y + y)
				var idx := y * rect.size.x + x
				if force_oob_byte >= 0:
					data[idx] = force_oob_byte
				elif solid_cells.has(cell):
					data[idx] = solid
				else:
					data[idx] = air
		return data


func test_all_air_is_clear() -> void:
	var wm := StubWM.new()
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_true()


func test_single_solid_cell_in_footprint_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.solid_cells[Vector2i(100, 100)] = true   # dead-center of the footprint
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_out_of_chunk_byte_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.force_oob_byte = 255                       # 255 marks cells outside any chunk
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_wrong_size_read_is_not_clear() -> void:
	var wm := StubWM.new()
	wm.force_wrong_size = true
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(100, 100))).is_false()


func test_null_world_manager_is_not_clear() -> void:
	assert_bool(_SpawnValidation.footprint_clear(null, Vector2(100, 100))).is_false()
