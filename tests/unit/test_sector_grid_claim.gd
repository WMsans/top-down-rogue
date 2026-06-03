extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _biome_with_one_boss_comp() -> Resource:
	var b := _BiomeDef.new()
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b

func test_boss_anchor_at_spaced_offset_only() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var s0 := grid.resolve_sector(Vector2i(10, -7))  # d=10 anchor
	assert_that(s0.is_boss).is_true()
	var s1 := grid.resolve_sector(Vector2i(10, -6))  # neighbor, within claim radius
	assert_that(s1.is_boss).is_false()
	assert_that(s1.is_claimed).is_true()

func test_boss_anchor_count_per_floor() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var count := 0
	for coord in _ring10_coords():
		if grid.resolve_sector(coord).is_boss:
			count += 1
	assert_that(count).is_equal(8)

func test_non_anchor_ring10_sectors_empty_or_claimed() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	for coord in _ring10_coords():
		var slot := grid.resolve_sector(coord)
		if not slot.is_boss:
			assert_that(slot.is_empty or slot.is_claimed).is_true()

func test_claim_extends_to_inner_neighbors() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var s := grid.resolve_sector(Vector2i(9, -9))
	assert_that(s.is_claimed).is_true()
	assert_that(s.is_empty).is_true()

func _ring10_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-10, 11):
		for y in range(-10, 11):
			if max(abs(x), abs(y)) == 10:
				out.append(Vector2i(x, y))
	out.sort_custom(func(a, b): return _clockwise_index(a) < _clockwise_index(b))
	return out

static func _clockwise_index(c: Vector2i) -> int:
	if c.x == 10:  return c.y + 10
	if c.y == 10:  return 20 + (10 - c.x)
	if c.x == -10: return 40 + (10 - c.y)
	return 60 + (c.x + 10)
