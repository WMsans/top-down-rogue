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
	var s0 := grid.resolve_sector(Vector2i(8, -7))  # d=8 anchor
	assert_that(s0.is_boss).is_true()
	var s1 := grid.resolve_sector(Vector2i(8, -6))  # neighbor, within claim radius
	assert_that(s1.is_boss).is_false()
	assert_that(s1.is_claimed).is_true()

func test_boss_anchor_count_per_floor() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var count := 0
	for coord in _ring8_coords():
		if grid.resolve_sector(coord).is_boss:
			count += 1
	assert_that(count).is_equal(12)

func test_non_anchor_ring8_sectors_empty_or_claimed() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	for coord in _ring8_coords():
		var slot := grid.resolve_sector(coord)
		if not slot.is_boss:
			assert_that(slot.is_empty or slot.is_claimed).is_true()

func test_claim_extends_to_inner_neighbors() -> void:
	var grid := _SectorGrid.new(0, _biome_with_one_boss_comp())
	var s := grid.resolve_sector(Vector2i(7, -7))
	assert_that(s.is_claimed).is_true()
	assert_that(s.is_empty).is_true()

func _ring8_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-8, 9):
		for y in range(-8, 9):
			if max(abs(x), abs(y)) == 8:
				out.append(Vector2i(x, y))
	out.sort_custom(func(a, b): return _clockwise_index(a) < _clockwise_index(b))
	return out

static func _clockwise_index(c: Vector2i) -> int:
	if c.x == 8:  return c.y + 8
	if c.y == 8:  return 16 + (8 - c.x)
	if c.x == -8: return 32 + (8 - c.y)
	return 48 + (c.x + 8)
