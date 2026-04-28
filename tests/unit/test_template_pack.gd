extends GdUnitTestSuite

const _TemplatePack = preload("res://src/core/template_pack.gd")
const _RoomTemplate = preload("res://src/core/room_template.gd")

func _make_template(path: String, size: int) -> Resource:
	var rt: Resource = _RoomTemplate.new()
	rt.png_path = path
	rt.size_class = size
	return rt

func test_register_returns_index() -> void:
	var pack := _TemplatePack.new()
	var rt: Resource = _make_template("res://assets/rooms/caves/blob_a.png", 64)
	var idx := pack.register(rt)
	assert_that(idx).is_equal(0)

func test_register_two_same_size_class() -> void:
	var pack := _TemplatePack.new()
	var a: Resource = _make_template("res://assets/rooms/caves/blob_a.png", 64)
	var b: Resource = _make_template("res://assets/rooms/caves/blob_b.png", 64)
	assert_that(pack.register(a)).is_equal(0)
	assert_that(pack.register(b)).is_equal(1)

func test_register_different_size_classes_keep_independent_indices() -> void:
	var pack := _TemplatePack.new()
	var a: Resource = _make_template("res://assets/rooms/caves/blob_a.png", 64)
	var b: Resource = _make_template("res://assets/rooms/caves/secret_a.png", 32)
	assert_that(pack.register(a)).is_equal(0)
	assert_that(pack.register(b)).is_equal(0)

func test_get_image_returns_loaded_image() -> void:
	var pack := _TemplatePack.new()
	var a: Resource = _make_template("res://assets/rooms/caves/blob_a.png", 64)
	var idx := pack.register(a)
	pack.build_arrays()
	var img := pack.get_image(64, idx)
	assert_that(img).is_not_null()
	assert_that(img.get_width()).is_equal(64)

func test_marker_pixels_returns_g_channel_positions() -> void:
	# blob_a was generated with 3 enemy markers (G=1)
	var pack := _TemplatePack.new()
	pack.register(_make_template("res://assets/rooms/caves/blob_a.png", 64))
	pack.build_arrays()
	var markers := pack.collect_markers(64, 0)
	var enemy_count := 0
	for m in markers:
		if m["type"] == 1:
			enemy_count += 1
	assert_that(enemy_count).is_equal(3)
