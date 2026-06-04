extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

func _make_comp() -> StatusComponent:
	return auto_free(StatusComponentScript.new())

func test_wet_extinguishes_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("wet", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# fire drained by WET_EXTINGUISH_RATE (4), wet by WET_EVAP_BONUS (1)
	assert_float(c.get_stain("on_fire")).is_equal_approx(1.0, 0.001)
	assert_float(c.get_stain("wet")).is_equal_approx(4.0, 0.001)

func test_bloody_dampens_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("bloody", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	assert_float(c.get_stain("on_fire")).is_equal_approx(3.5, 0.001)  # -1.5

func test_oiled_feeds_fire() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 1.0)
	c.add_stain("oiled", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# oiled consumed by OIL_FEED_RATE (2) -> 3; fire gains 2*OIL_FIRE_GAIN(1.5)=3 -> 4
	assert_float(c.get_stain("oiled")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("on_fire")).is_equal_approx(4.0, 0.001)

func test_wet_plus_chilly_makes_frozen() -> void:
	var c := _make_comp()
	c.add_stain("wet", 5.0)
	c.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# conv = min(5,5, WET_FREEZE_RATE(2)) = 2
	assert_float(c.get_stain("wet")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("chilly")).is_equal_approx(3.0, 0.001)
	assert_float(c.get_stain("frozen")).is_equal_approx(2.0, 0.001)

func test_fire_melts_cold() -> void:
	var c := _make_comp()
	c.add_stain("on_fire", 5.0)
	c.add_stain("frozen", 5.0)
	c.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(c, 1.0)
	# FIRE_MELT_RATE (3) drained from both
	assert_float(c.get_stain("frozen")).is_equal_approx(2.0, 0.001)
	assert_float(c.get_stain("chilly")).is_equal_approx(2.0, 0.001)

func test_chilly_ramps_to_frozen() -> void:
	var c := _make_comp()
	c.add_stain("chilly", 5.0)  # >= CHILLY_FREEZE_THRESHOLD (4)
	StatusRegistry.apply_reactions(c, 1.0)
	# CHILLY_RAMP_RATE (1) moved chilly->frozen
	assert_float(c.get_stain("chilly")).is_equal_approx(4.0, 0.001)
	assert_float(c.get_stain("frozen")).is_equal_approx(1.0, 0.001)
