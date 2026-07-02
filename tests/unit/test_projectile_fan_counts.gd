extends GdUnitTestSuite

func test_fireball_fan_count_is_three() -> void:
	var m := FireballFanModifier.new()
	assert_int(m.FAN_COUNT).is_equal(3)

func test_icicle_volley_is_three_piercing() -> void:
	var m := IcicleVolleyModifier.new()
	assert_int(m.FAN_COUNT).is_equal(3)
	assert_bool(m.PIERCING).is_true()
