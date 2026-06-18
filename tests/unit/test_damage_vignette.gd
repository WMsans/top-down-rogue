extends GdUnitTestSuite

const DamageVignetteScript = preload("res://src/core/juice/damage_vignette.gd")

func test_set_burn_intensity_raises_ember() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_equal_approx(0.0, 0.001)
	v.set_burn_intensity(1.0)
	for i in 30:
		await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_greater(0.1)

func test_set_burn_intensity_zero_decays_ember() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	v.set_burn_intensity(1.0)
	for i in 30:
		await get_tree().process_frame
	v.set_burn_intensity(0.0)
	for i in 60:
		await get_tree().process_frame
	assert_float(v.get_ember_intensity()).is_less(0.05)
