extends GdUnitTestSuite

const NavField = preload("res://src/core/nav/nav_field.gd")

class StubWM extends Node:
	var region: PackedByteArray
	func read_region(_rect: Rect2i) -> PackedByteArray:
		return region

func _region_all(mat: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(256 * 256)
	b.fill(mat)
	return b

func test_dirty_chunk_becomes_solid_after_update() -> void:
	var wm = auto_free(StubWM.new())
	add_child(wm)
	wm.region = _region_all(MaterialRegistry.MAT_STONE)
	var nav = NavField.new(wm)
	nav.mark_dirty(Vector2i(0, 0))
	nav.update(Vector2(0, 0), 0.0)
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_true()

func test_air_chunk_is_open() -> void:
	var wm = auto_free(StubWM.new())
	add_child(wm)
	wm.region = _region_all(MaterialRegistry.MAT_AIR)
	var nav = NavField.new(wm)
	nav.mark_dirty(Vector2i(0, 0))
	nav.update(Vector2(0, 0), 0.0)
	assert_bool(nav.is_solid_world(Vector2(4, 4))).is_false()
