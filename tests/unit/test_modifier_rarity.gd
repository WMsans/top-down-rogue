extends GdUnitTestSuite


func test_default_modifier_rarity_is_common() -> void:
	var m := Modifier.new()
	assert_int(m.rarity).is_equal(DropTable.ItemTier.COMMON)


func test_script_modifier_rarity_from_csv_common() -> void:
	var m: Modifier = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(m).is_not_null()
	assert_int(m.rarity).is_equal(DropTable.ItemTier.COMMON)


func test_script_modifier_rarity_from_csv_uncommon() -> void:
	var m: Modifier = WeaponRegistry._make_modifier("green_crescent")
	assert_that(m).is_not_null()
	assert_int(m.rarity).is_equal(DropTable.ItemTier.UNCOMMON)


func test_data_modifier_rarity_from_csv_common() -> void:
	var m: Modifier = WeaponRegistry._make_modifier("oil_emitter")
	assert_that(m).is_not_null()
	assert_int(m.rarity).is_equal(DropTable.ItemTier.COMMON)


func test_data_modifier_rarity_from_csv_uncommon() -> void:
	var m: Modifier = WeaponRegistry._make_modifier("pyroclast")
	assert_that(m).is_not_null()
	assert_int(m.rarity).is_equal(DropTable.ItemTier.UNCOMMON)
