extends GdUnitTestSuite

func _make(id: String) -> Modifier:
	return WeaponRegistry._make_modifier(id)


func test_all_24_combo_modifiers_registered_and_droppable() -> void:
	var scripted := [
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	var data_driven := ["spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge"]
	for id in scripted:
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_true()
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
	for id in data_driven:
		assert_that(WeaponRegistry._make_modifier(id)).is_not_null()
		assert_bool(WeaponRegistry.modifier_scripts.has(id)).is_false()


func test_all_24_combo_modifiers_have_csv_rows() -> void:
	var all_24 := [
		"spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge",
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	for id in all_24:
		assert_bool(WeaponRegistry._modifier_data.has(id)).is_true()
		var row: Dictionary = WeaponRegistry._modifier_data[id]
		assert_str(row.get("rarity", "")).is_not_empty()
		assert_str(row.get("category", "")).is_not_empty()


func test_combo_modifier_rarity_spread_is_4c_13u_7r() -> void:
	var c := 0
	var u := 0
	var r := 0
	var all_24 := [
		"spark_plug", "deepfreeze", "hemophilia", "backdraft", "riptide", "plague_carrier", "greedy_edge",
		"frostshatter", "combustion", "necrosis", "rupture",
		"echo_strike", "overclock", "mirror_slot", "catalyst_bond",
		"keystone", "twin_trigger", "flywheel",
		"last_stand", "overkill", "evolving_edge", "pendulum", "headsman", "slot_harmony",
	]
	for id in all_24:
		var rarity: String = WeaponRegistry._modifier_data[id].get("rarity", "")
		match rarity:
			"Common":
				c += 1
			"Uncommon":
				u += 1
			"Rare":
				r += 1
	assert_int(c).is_equal(4)
	assert_int(u).is_equal(13)
	assert_int(r).is_equal(7)


func test_total_modifier_count_is_81() -> void:
	var total := 0
	for tier in WeaponRegistry.modifier_tiers.keys():
		total += WeaponRegistry.modifier_tiers[tier].size()
	assert_int(total).is_equal(81)
