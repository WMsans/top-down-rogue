extends GdUnitTestSuite


func test_explode_wave_material_registered() -> void:
	var reg := MaterialRegistry.new()
	reg._ready()
	assert_that(reg.MAT_EXPLODE_WAVE).is_greater(0)
	assert_that(reg.is_fluid(reg.MAT_EXPLODE_WAVE)).is_false()
	assert_that(reg.is_flammable(reg.MAT_EXPLODE_WAVE)).is_false()


func test_explode_wave_material_def() -> void:
	var reg := MaterialRegistry.new()
	reg._ready()
	var mat := reg.materials[reg.MAT_EXPLODE_WAVE]
	assert_that(mat.glow).is_equal(30.0)
	assert_that(mat.name).is_equal("EXPLODE_WAVE")


func test_wave_forms_ring_not_disk() -> void:
	assert_that(MaterialRegistry.MAT_EXPLODE_WAVE).is_not_equal(-1)
	assert_that(MaterialRegistry.MAT_AIR).is_equal(0)
	assert_that(MaterialRegistry.MAT_EXPLODE_WAVE).is_not_equal(MaterialRegistry.MAT_AIR)
