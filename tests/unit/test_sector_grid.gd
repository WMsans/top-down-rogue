extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _make_biome() -> Resource:
	var b := _BiomeDef.new()
	var rt := _RoomTemplate.new()
	rt.png_path = "rt0"
	rt.weight = 1.0
	var rt2 := _RoomTemplate.new()
	rt2.png_path = "rt1"
	rt2.weight = 2.0
	var templates: Array[RoomTemplate] = [rt, rt2]
	b.room_templates = templates
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b


func _first_boss_anchor() -> Vector2i:
	for x in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
		for y in range(-_SectorGrid.WALL_INNER_SECTORS, _SectorGrid.WALL_INNER_SECTORS + 1):
			if _SectorGrid.is_boss_anchor(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i.MAX


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
	var anchor := _first_boss_anchor()
	assert_that(anchor).is_not_equal(Vector2i.MAX)
	var slot := grid.resolve_sector(anchor)
	assert_that(slot.is_boss).is_true()

func test_outside_boss_ring_is_empty() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	# A non-anchor sector at/after the wall radius is empty (becomes bedrock).
	var slot := grid.resolve_sector(Vector2i(9, 1))  # dist 9 >= wall radius 8, not an anchor
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
			if g1.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.WALL_INNER_SECTORS:
				continue
			var s1 := g1.resolve_sector(c)
			var s2 := g2.resolve_sector(c)
			if s1.template_index != s2.template_index or s1.is_empty != s2.is_empty:
				diff += 1
	assert_that(diff > 30).is_true()

func test_rotation_is_zero_for_non_rotatable() -> void:
	var grid := _SectorGrid.new(12345, _make_biome())
	var anchor := _first_boss_anchor()
	var slot := grid.resolve_sector(anchor)  # boss anchor, rotatable=false
	assert_that(slot.rotation).is_equal(0)


func _make_elite_biome() -> Resource:
	var b := _BiomeDef.new()
	var elite := _RoomTemplate.new()
	elite.png_path = "elite"
	elite.weight = 50.0          # dominate the roll so non-empty ≈ always elite
	elite.is_elite_chest = true
	var templates: Array[RoomTemplate] = [elite]
	b.room_templates = templates
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	return b


func test_elite_room_gated_near_origin() -> void:
	var grid := _SectorGrid.new(4242, _make_elite_biome())
	for x in range(-2, 3):
		for y in range(-2, 3):
			var c := Vector2i(x, y)
			if grid.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.ELITE_MIN_DIST:
				continue
			var slot := grid.resolve_sector(c)
			var tmpl := grid.get_template_for_slot(slot)
			assert_bool(tmpl != null and tmpl.is_elite_chest).is_false()


func test_empty_fraction_matches_lowered_weight() -> void:
	var b := _BiomeDef.new()
	var rt := _RoomTemplate.new()
	rt.png_path = "rt"
	rt.weight = 2.0
	var templates: Array[RoomTemplate] = [rt]
	b.room_templates = templates
	var comp := _ArenaComposition.new()
	comp.arena_kind = &"boss"
	b.boss_compositions = [comp]
	var grid := _SectorGrid.new(777, b)
	var empty := 0
	var total := 0
	for x in range(-6, 7):
		for y in range(-6, 7):
			var c := Vector2i(x, y)
			if grid.chebyshev_distance(c, Vector2i.ZERO) >= _SectorGrid.WALL_INNER_SECTORS - _SectorGrid.BOSS_CLAIM_RADIUS:
				continue
			total += 1
			if grid.resolve_sector(c).is_empty:
				empty += 1
	var frac := float(empty) / float(total)
	assert_float(frac).is_equal_approx(0.333, 0.08)


func test_elite_room_allowed_beyond_min_dist() -> void:
	var grid := _SectorGrid.new(4242, _make_elite_biome())
	var found_elite := false
	for x in range(-7, 8):
		for y in range(-7, 8):
			var c := Vector2i(x, y)
			var d := grid.chebyshev_distance(c, Vector2i.ZERO)
			if d < _SectorGrid.ELITE_MIN_DIST or d >= _SectorGrid.WALL_INNER_SECTORS:
				continue
			var slot := grid.resolve_sector(c)
			var tmpl := grid.get_template_for_slot(slot)
			if tmpl != null and tmpl.is_elite_chest:
				found_elite = true
	assert_bool(found_elite).is_true()
