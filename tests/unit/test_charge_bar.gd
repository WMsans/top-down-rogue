extends GdUnitTestSuite

const ChargeBarScript = preload("res://src/ui/charge_bar.gd")

func test_set_ratio_clamps_high() -> void:
	var bar: ChargeBar = auto_free(ChargeBarScript.new())
	bar.set_ratio(2.0)
	assert_float(bar._ratio).is_equal_approx(1.0, 0.001)

func test_set_ratio_clamps_low() -> void:
	var bar: ChargeBar = auto_free(ChargeBarScript.new())
	bar.set_ratio(-0.5)
	assert_float(bar._ratio).is_equal_approx(0.0, 0.001)

func test_set_active_toggles_visibility() -> void:
	var bar: ChargeBar = auto_free(ChargeBarScript.new())
	bar.set_active(true)
	assert_bool(bar.visible).is_true()
	bar.set_active(false)
	assert_bool(bar.visible).is_false()

func test_inactive_resets_to_anchor() -> void:
	var bar: ChargeBar = auto_free(ChargeBarScript.new())
	bar.set_ratio(1.0)
	bar.set_active(false)
	assert_vector(bar.position).is_equal(ChargeBarScript.ANCHOR)
