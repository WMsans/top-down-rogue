extends GdUnitTestSuite

const _BiomeDef = preload("res://src/core/biome_def.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func test_fixed_anchors_default_empty() -> void:
	var b := _BiomeDef.new()
	assert_that(b.fixed_anchors).is_equal({})

func test_fixed_anchors_holds_template_by_sector() -> void:
	var b := _BiomeDef.new()
	var tmpl := _RoomTemplate.new()
	b.fixed_anchors[Vector2i(0, 0)] = tmpl
	assert_that(b.fixed_anchors.has(Vector2i(0, 0))).is_true()
	assert_that(b.fixed_anchors[Vector2i(0, 0)]).is_equal(tmpl)
