extends GdUnitTestSuite

func test_barrel_constants() -> void:
	const OilBarrelScript := preload("res://src/props/oil_barrel.gd")
	assert_that(OilBarrelScript.MAX_HP).is_equal(3)
	assert_that(OilBarrelScript.SPLASH_RADIUS).is_equal(4.0)
	assert_that(OilBarrelScript.DUMP_RADIUS).is_equal(8.0)

func test_gas_vent_constants() -> void:
	const GasVentScript := preload("res://src/props/gas_vent.gd")
	assert_that(GasVentScript.EMIT_INTERVAL).is_equal(5.0)
	assert_that(GasVentScript.EMIT_RADIUS).is_equal(6.0)
	assert_that(GasVentScript.EMIT_DENSITY).is_equal(80)

func test_poisoned_status_exists() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_that(def).is_not_null()
	assert_that(def.display_name).is_equal("Poisoned")
	assert_that(def.category).is_equal(StatusRegistry.StatusDefScript.Category.HARMFUL)

func test_poisoned_properties() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_that(def.decay_rate).is_equal(0.4)
	assert_that(def.active_threshold).is_equal(0.3)
	assert_that(def.burn_dps).is_equal(2.0)
	assert_that(def.blocks_movement).is_false()
	assert_that(def.slow_multiplier).is_equal(0.6)

func test_gas_material_maps_to_poisoned() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_GAS)
	assert_that(result).is_equal("poisoned")

func test_oil_material_maps_to_oiled() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_OIL)
	assert_that(result).is_equal("oiled")

func test_poisoned_slow_multiplier() -> void:
	var multiplier := StatusRegistry.get_slow_multiplier("poisoned")
	assert_that(multiplier).is_equal(0.6)

func test_poisoned_burn_dps() -> void:
	var dps := StatusRegistry.get_burn_dps("poisoned")
	assert_that(dps).is_equal(2.0)

func test_poisoned_does_not_block_movement() -> void:
	var blocks := StatusRegistry.blocks_movement("poisoned")
	assert_that(blocks).is_false()