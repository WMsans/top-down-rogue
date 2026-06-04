extends GdUnitTestSuite

func test_make_modifier_overlays_csv_metadata() -> void:
	var mod = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(mod).is_not_null()
	assert_that(mod.name).is_equal("Lava Emitter")
	assert_that(mod.description).is_equal("Spawns lava around the user when the weapon is used.")
	assert_that(mod.suppresses_base_use).is_false()

func test_make_modifier_unknown_id_returns_null() -> void:
	var mod = WeaponRegistry._make_modifier("does_not_exist")
	assert_that(mod).is_null()
