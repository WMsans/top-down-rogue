extends GdUnitTestSuite

const GasVentScript := preload("res://src/props/gas_vent.gd")

func test_vent_timer_starts_at_zero() -> void:
	var vent := auto_free(GasVentScript.new())
	assert_that(vent._timer).is_equal(0.0)

func test_vent_constants() -> void:
	assert_that(GasVentScript.EMIT_INTERVAL).is_equal(5.0)
	assert_that(GasVentScript.EMIT_RADIUS).is_equal(6.0)
	assert_that(GasVentScript.EMIT_DENSITY).is_equal(80)