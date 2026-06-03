extends GdUnitTestSuite

const BIOMES := ["caves", "mines", "magma", "frozen", "vault"]

func test_each_shop_png_is_256_with_single_shop_marker() -> void:
	for biome in BIOMES:
		var img := Image.load_from_file("res://assets/rooms/%s/shop_a.png" % biome)
		assert_that(img).is_not_null()
		assert_that(img.get_width()).is_equal(256)
		assert_that(img.get_height()).is_equal(256)
		var shop_markers := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c := img.get_pixel(x, y)
				if int(c.a8) == 255 and int(c.g8) == 4:
					shop_markers += 1
		assert_that(shop_markers).is_equal(1)

func test_shop_png_has_wood_wall_border() -> void:
	var img := Image.load_from_file("res://assets/rooms/vault/shop_a.png")
	# Corner is wall: R = MAT_WOOD (1), written (A=255)
	var corner := img.get_pixel(0, 0)
	assert_that(int(corner.r8)).is_equal(1)
	assert_that(int(corner.a8)).is_equal(255)
	# Center is the marker cell on AIR (R=0)
	var center := img.get_pixel(128, 128)
	assert_that(int(center.r8)).is_equal(0)
	assert_that(int(center.g8)).is_equal(4)
