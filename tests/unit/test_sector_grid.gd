extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func _make_biome() -> Resource:
	var b: Resource = _BiomeDef.new()
	var rt: Resource = _RoomTemplate.new()
	rt.png_path = "rt0"
	rt.weight = 1.0
	var rt2: Resource = _RoomTemplate.new()
	rt2.png_path = "rt1"
	rt2.weight = 2.0
	b.room_templates = [rt, rt2]
	var boss: Resource = _RoomTemplate.new()
	boss.png_path = "boss"
	boss.is_boss = true
	boss.rotatable = false
	b.boss_templates = [boss]
	return b

func test_world_to_sector_origin() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	assert_that(grid.world_to_sector(Vector2.ZERO)).is_equal(Vector2i.ZERO)

func test_world_to_sector_positive() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	assert_that(grid.world_to_sector(Vector2(384, 0))).is_equal(Vector2i(1, 0))

func test_world_to_sector_negative() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	assert_that(grid.world_to_sector(Vector2(-1, -1))).is_equal(Vector2i(-1, -1))

func test_sector_to_world_center() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	assert_that(grid.sector_to_world_center(Vector2i.ZERO)).is_equal(Vector2i(192, 192))

func test_chebyshev_symmetric() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var a := Vector2i(2, -3)
	var b := Vector2i(-1, 5)
	assert_that(grid.chebyshev_distance(a, b)).is_equal(grid.chebyshev_distance(b, a))

func test_boss_ring_returns_boss_slot() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var slot := grid.resolve_sector(Vector2i(10, 0))
	assert_that(slot.is_boss).is_true()

func test_outside_boss_ring_is_empty() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var slot := grid.resolve_sector(Vector2i(11, 0))
	assert_that(slot.is_empty).is_true()

func test_inside_ring_not_boss() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var slot := grid.resolve_sector(Vector2i(5, 0))
	assert_that(slot.is_boss).is_false()

func test_resolve_sector_deterministic() -> void:
	var b: Resource = _make_biome()
	var g1 := _SectorGrid.new(99999, b)
	var g2 := _SectorGrid.new(99999, b)
	var coord := Vector2i(3, -2)
	var s1 := g1.resolve_sector(coord)
	var s2 := g2.resolve_sector(coord)
	assert_that(s1.template_index).is_equal(s2.template_index)
	assert_that(s1.rotation).is_equal(s2.rotation)
	assert_that(s1.is_empty).is_equal(s2.is_empty)

func test_resolve_sector_seed_changes() -> void:
	var b: Resource = _make_biome()
	var g1 := _SectorGrid.new(1, b)
	var g2 := _SectorGrid.new(2, b)
	var diff := 0
	for x in range(-5, 5):
		for y in range(-5, 5):
			var c := Vector2i(x, y)
			if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.BOSS_RING_DISTANCE:
				continue
			var s1 := g1.resolve_sector(c)
			var s2 := g2.resolve_sector(c)
			if s1.template_index != s2.template_index or s1.is_empty != s2.is_empty:
				diff += 1
	assert_that(diff > 30).is_true()

func test_rotation_is_zero_for_non_rotatable() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var slot := grid.resolve_sector(Vector2i(10, 0))  # boss, rotatable=false
	assert_that(slot.rotation).is_equal(0)
