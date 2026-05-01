extends GdUnitTestSuite

# BiomeDef, PoolDef, RoomTemplate now registered as native C++ classes

func test_biome_def_has_defaults() -> void:
	var b := BiomeDef.new()
	assert_that(b.cave_noise_scale).is_equal(0.008)
	assert_that(b.cave_threshold).is_equal(0.42)
	assert_that(b.octaves).is_equal(5)
	assert_that(b.secret_ring_thickness).is_equal(3)

func test_pool_def_construction() -> void:
	var p := PoolDef.new()
	p.material_id = 7
	p.noise_scale = 0.005
	p.noise_threshold = 0.6
	assert_that(p.material_id).is_equal(7)

func test_room_template_defaults() -> void:
	var rt := RoomTemplate.new()
	assert_that(rt.weight).is_equal(1.0)
	assert_that(rt.size_class).is_equal(64)
	assert_that(rt.is_secret).is_false()
	assert_that(rt.is_boss).is_false()
	assert_that(rt.rotatable).is_true()
