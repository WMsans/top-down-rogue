extends GdUnitTestSuite

const BIOMES := ["caves", "mines", "magma", "frozen", "vault"]
const SIZE := 128
const MAT_WOOD := 1

func test_each_shop_png_is_128_with_single_shop_marker() -> void:
	for biome in BIOMES:
		var img := Image.load_from_file("res://assets/rooms/%s/shop_a.png" % biome)
		assert_that(img).is_not_null()
		assert_that(img.get_width()).is_equal(SIZE)
		assert_that(img.get_height()).is_equal(SIZE)
		var shop_markers := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if int(c.a8) == 255 and int(c.g8) == 4:
					shop_markers += 1
		assert_that(shop_markers).is_equal(1)

func test_shop_png_has_no_wall_and_blends_into_cave() -> void:
	var img := Image.load_from_file("res://assets/rooms/vault/shop_a.png")
	# Corners are untouched (A=0) so the native cave shows through.
	for corner in [Vector2i(0, 0), Vector2i(SIZE - 1, 0), Vector2i(0, SIZE - 1), Vector2i(SIZE - 1, SIZE - 1)]:
		assert_that(int(img.get_pixelv(corner).a8)).is_equal(0)
	# No wood anywhere: the fence is gone.
	for y in range(SIZE):
		for x in range(SIZE):
			var c := img.get_pixel(x, y)
			if int(c.a8) == 255:
				assert_that(int(c.r8)).is_not_equal(MAT_WOOD)
	# Center is the marker cell on AIR (R=0)
	var center := img.get_pixel(SIZE / 2, SIZE / 2)
	assert_that(int(center.r8)).is_equal(0)
	assert_that(int(center.g8)).is_equal(4)

func test_shop_clearing_covers_the_stall_footprint() -> void:
	var img := Image.load_from_file("res://assets/rooms/caves/shop_a.png")
	for dy in range(-40, 41, 5):
		for dx in range(-50, 51, 5):
			var c := img.get_pixel(SIZE / 2 + dx, SIZE / 2 + dy)
			assert_that(int(c.a8)).override_failure_message("(%d,%d) not carved" % [dx, dy]).is_equal(255)
