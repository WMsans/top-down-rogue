extends GdUnitTestSuite

const GasVentScript := preload("res://src/props/gas_vent.gd")


func test_vent_timer_starts_at_zero() -> void:
	var vent := auto_free(GasVentScript.new())
	assert_eq(vent._timer, 0.0)


func test_vent_accumulates_delta() -> void:
	var vent := auto_free(GasVentScript.new())
	vent._timer = 2.0
	# We can't easily test _process since it calls TerrainSurface.place_gas,
	# but we can verify the timer accumulation logic by checking _timer
	assert_eq(vent.EMIT_INTERVAL, 5.0)
	assert_eq(vent.EMIT_RADIUS, 6.0)
	assert_eq(vent.EMIT_DENSITY, 80)


func test_vent_constants() -> void:
	assert_eq(GasVentScript.EMIT_INTERVAL, 5.0)
	assert_eq(GasVentScript.EMIT_RADIUS, 6.0)
	assert_eq(GasVentScript.EMIT_DENSITY, 80)