extends GdUnitTestSuite

const PassabilityGrid = preload("res://src/core/nav/passability_grid.gd")
const _SpawnValidation = preload("res://src/core/spawn_validation.gd")

# Stub world_manager for spawn validation: read_region is all MAT_AIR, so only
# prop blockers in the nav grid can reject a footprint.
class StubNavField extends RefCounted:
	var grid

class StubWM extends RefCounted:
	var nav_field

	func read_region(rect: Rect2i) -> PackedByteArray:
		var data := PackedByteArray()
		data.resize(rect.size.x * rect.size.y)
		data.fill(MaterialRegistry.MAT_AIR)
		return data

# 32x32 cells per 256px chunk at 8px cells, all open.
func _zero_tile() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	return t

func _grid_with_tile() -> PassabilityGrid:
	var g := PassabilityGrid.new(8, 256, PackedByteArray())
	g.set_tile(Vector2i(0, 0), _zero_tile())
	return g

func test_blocker_marks_cells_solid() -> void:
	var g := _grid_with_tile()
	g.add_blocker(Vector2(100, 100), 6.0)
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_true()
	assert_bool(g.is_solid_world(Vector2(140, 100))).is_false()

func test_blocker_survives_tile_update() -> void:
	var g := _grid_with_tile()
	g.add_blocker(Vector2(100, 100), 6.0)
	# The GPU readback refills the chunk tile wholesale; blockers live apart from it.
	g.set_tile(Vector2i(0, 0), _zero_tile())
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_true()

func test_overlapping_blockers_refcount() -> void:
	var g := _grid_with_tile()
	g.add_blocker(Vector2(100, 100), 6.0)
	g.add_blocker(Vector2(100, 100), 6.0)
	g.remove_blocker(Vector2(100, 100), 6.0)
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_true()
	g.remove_blocker(Vector2(100, 100), 6.0)
	assert_bool(g.is_solid_world(Vector2(100, 100))).is_false()

func test_footprint_rejects_prop_blocker() -> void:
	var wm := StubWM.new()
	wm.nav_field = StubNavField.new()
	wm.nav_field.grid = _grid_with_tile()
	wm.nav_field.grid.add_blocker(Vector2(50, 50), 6.0)
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(50, 50))).is_false()
	assert_bool(_SpawnValidation.footprint_clear(wm, Vector2(200, 200))).is_true()
