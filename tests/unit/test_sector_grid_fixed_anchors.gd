extends GdUnitTestSuite

const _SectorGrid = preload("res://src/core/sector_grid.gd")
const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")
const _ArenaComposition = preload("res://src/core/arena_composition.gd")

func _make_biome_with_anchor(coord: Vector2i, cavern_carve: bool) -> _BiomeDef:
	var b := _BiomeDef.new()
	var comp := _ArenaComposition.new()
	var tmpl := _RoomTemplate.new()
	tmpl.cavern_carve = cavern_carve
	tmpl.composition = comp
	tmpl.size_class = 96
	b.fixed_anchors[coord] = tmpl
	return b

func test_resolve_sector_returns_fixed_anchor_template() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	var slot = grid.resolve_sector(Vector2i(0, 0))
	assert_that(slot.template_override).is_equal(biome.fixed_anchors[Vector2i(0, 0)])
	assert_that(slot.composition).is_equal(biome.fixed_anchors[Vector2i(0, 0)].composition)
	assert_that(slot.is_empty).is_false()
	assert_that(slot.is_boss).is_false()
	assert_that(slot.template_size).is_equal(96)

func test_resolve_sector_non_anchor_unchanged() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	var slot = grid.resolve_sector(Vector2i(3, 2))
	assert_that(slot.template_override).is_null()

func test_get_template_for_slot_returns_override() -> void:
	var biome := _make_biome_with_anchor(Vector2i(0, 0), true)
	var grid := _SectorGrid.new(12345, biome)
	var slot = grid.resolve_sector(Vector2i(0, 0))
	var tmpl = grid.get_template_for_slot(slot)
	assert_that(tmpl).is_equal(biome.fixed_anchors[Vector2i(0, 0)])
