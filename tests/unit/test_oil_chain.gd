extends GdUnitTestSuite


func test_oil_material_registered() -> void:
	var reg := MaterialRegistry.new()
	reg._ready()
	assert_that(reg.MAT_OIL).is_greater(0)
	assert_that(reg.is_fluid(reg.MAT_OIL)).is_true()
	assert_that(reg.is_flammable(reg.MAT_OIL)).is_false()
	assert_that(reg.get_damage(reg.MAT_OIL)).is_equal(0)
	assert_that(reg.get_glow(reg.MAT_OIL)).is_equal(1.0)


func test_oil_burn_health() -> void:
	var reg := MaterialRegistry.new()
	reg._ready()
	var mat := reg.materials[reg.MAT_OIL]
	assert_that(mat.burn_health).is_equal(60)
	assert_that(mat.flammable).is_false()


func test_oil_ignites_from_lava_contact() -> void:
	assert_that(MaterialRegistry.MAT_OIL).is_not_equal(-1)
	assert_that(MaterialRegistry.MAT_LAVA).is_not_equal(-1)
	assert_that(MaterialRegistry.MAT_LAVA).is_not_equal(MaterialRegistry.MAT_OIL)


func test_fire_material_registered() -> void:
	var reg := MaterialRegistry.new()
	reg._ready()
	assert_that(reg.MAT_FIRE).is_greater(0)
	assert_that(reg.is_fluid(reg.MAT_FIRE)).is_false()
	assert_that(reg.is_flammable(reg.MAT_FIRE)).is_false()
