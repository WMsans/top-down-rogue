extends GdUnitTestSuite

const StatusRegistryScript := preload("res://src/autoload/status_registry.gd")


func test_poisoned_status_exists() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_not_null(def)
	assert_eq(def.display_name, "Poisoned")
	assert_eq(def.category, StatusRegistryScript.StatusDef.Category.HARMFUL)


func test_poisoned_properties() -> void:
	var def := StatusRegistry.get_def("poisoned")
	assert_eq(def.decay_rate, 0.4)
	assert_eq(def.active_threshold, 0.3)
	assert_eq(def.burn_dps, 2.0)
	assert_eq(def.blocks_movement, false)
	assert_eq(def.slow_multiplier, 0.6)


func test_gas_material_maps_to_poisoned() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_GAS)
	assert_eq(result, "poisoned")


func test_oil_material_maps_to_oiled() -> void:
	var result := StatusRegistry.stain_for_material(MaterialRegistry.MAT_OIL)
	assert_eq(result, "oiled")


func test_poisoned_slow_multiplier() -> void:
	var multiplier := StatusRegistry.get_slow_multiplier("poisoned")
	assert_eq(multiplier, 0.6)


func test_poisoned_burn_dps() -> void:
	var dps := StatusRegistry.get_burn_dps("poisoned")
	assert_eq(dps, 2.0)