extends GdUnitTestSuite

const StatusComponentScript = preload("res://src/status/status_component.gd")

func _sc() -> StatusComponent:
	return auto_free(StatusComponentScript.new())

func test_wet_drains_fire() -> void:
	var sc := _sc()
	sc.add_stain("on_fire", 5.0)
	sc.add_stain("wet", 5.0)
	var before: float = sc.get_stain("on_fire")
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("on_fire")).is_less(before)

func test_oil_feeds_fire() -> void:
	var sc := _sc()
	sc.add_stain("on_fire", 2.0)
	sc.add_stain("oiled", 5.0)
	var before_fire: float = sc.get_stain("on_fire")
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("on_fire")).is_greater(before_fire)
	assert_float(sc.get_stain("oiled")).is_less(5.0)

func test_wet_and_chilly_make_frozen() -> void:
	var sc := _sc()
	sc.add_stain("wet", 5.0)
	sc.add_stain("chilly", 5.0)
	StatusRegistry.apply_reactions(sc, 0.5)
	assert_float(sc.get_stain("frozen")).is_greater(0.0)
