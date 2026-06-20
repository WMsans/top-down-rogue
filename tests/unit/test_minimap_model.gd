extends GdUnitTestSuite

const MinimapModel = preload("res://src/ui/minimap/minimap_model.gd")

func test_images_are_square_and_sized() -> void:
	var m := MinimapModel.new()
	assert_that(m.world_cells > 0).is_true()
	assert_that(m.terrain_img.get_width()).is_equal(m.world_cells)
	assert_that(m.terrain_img.get_height()).is_equal(m.world_cells)
	assert_that(m.reveal_img.get_width()).is_equal(m.world_cells)

func test_world_to_cell_origin_corner() -> void:
	var m := MinimapModel.new()
	assert_that(m.world_to_cell(Vector2(-m.world_half_px, -m.world_half_px))).is_equal(Vector2i(0, 0))

func test_world_to_uv_center_is_half() -> void:
	var m := MinimapModel.new()
	var uv := m.world_to_uv(Vector2.ZERO)
	assert_that(abs(uv.x - 0.5) < 0.01).is_true()
	assert_that(abs(uv.y - 0.5) < 0.01).is_true()

func test_reveal_marks_chunk_center() -> void:
	var m := MinimapModel.new()
	m.reveal_chunk(Vector2i(0, 0))
	assert_that(m.is_revealed_world(Vector2(128, 128))).is_true()

func test_unrevealed_far_cell_is_fogged() -> void:
	var m := MinimapModel.new()
	m.reveal_chunk(Vector2i(0, 0))
	assert_that(m.is_revealed_world(Vector2(2000, 2000))).is_false()

func test_adjacent_reveals_merge_across_seam() -> void:
	var m := MinimapModel.new()
	m.reveal_chunk(Vector2i(0, 0))
	m.reveal_chunk(Vector2i(1, 0))
	assert_that(m.is_revealed_world(Vector2(256, 128))).is_true()


func _solid_tile() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(1)
	return t


func _floor_tile() -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(32 * 32)
	t.fill(0)
	return t


func test_stamp_solid_tile_marks_wall() -> void:
	var m := MinimapModel.new()
	m.stamp_terrain(Vector2i(0, 0), _solid_tile())
	var c := m.world_to_cell(Vector2(128, 128))
	assert_that(m.terrain_img.get_pixel(c.x, c.y).r > 0.5).is_true()


func test_stamp_floor_tile_stays_floor() -> void:
	var m := MinimapModel.new()
	m.stamp_terrain(Vector2i(0, 0), _floor_tile())
	var c := m.world_to_cell(Vector2(128, 128))
	assert_that(m.terrain_img.get_pixel(c.x, c.y).r < 0.5).is_true()


func test_stamp_ignores_undersized_tile() -> void:
	var m := MinimapModel.new()
	m.stamp_terrain(Vector2i(0, 0), PackedByteArray())  # must not crash
	var c := m.world_to_cell(Vector2(128, 128))
	assert_that(m.terrain_img.get_pixel(c.x, c.y).r < 0.5).is_true()
