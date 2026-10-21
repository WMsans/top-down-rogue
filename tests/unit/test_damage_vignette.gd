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

func test_pulse_takes_no_damage_argument() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	await get_tree().process_frame
	v.pulse()
	var peak := 0.0
	for i in 30:
		await get_tree().process_frame
		peak = maxf(peak, v._get_intensity())
	assert_float(peak).is_greater(0.0)

func test_low_health_at_one_of_three_hearts() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	await get_tree().process_frame
	v._on_health_changed(1, 3)
	assert_bool(v._is_low_health).is_true()

func test_not_low_health_at_two_of_three_hearts() -> void:
	var v: DamageVignette = auto_free(DamageVignetteScript.new())
	add_child(v)
	await get_tree().process_frame
	v._on_health_changed(1, 3)
	v._on_health_changed(2, 3)
	assert_bool(v._is_low_health).is_false()
