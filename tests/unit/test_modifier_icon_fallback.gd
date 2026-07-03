extends GdUnitTestSuite

const PLACEHOLDER := preload("res://textures/wall.png")


func test_data_modifier_gets_placeholder_icon() -> void:
	var mod: Modifier = WeaponRegistry._make_modifier("adrenaline")
	assert_that(mod).is_not_null()
	assert_that(mod.icon_texture).is_equal(PLACEHOLDER)


func test_script_modifier_keeps_its_own_icon() -> void:
	var mod: Modifier = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(mod).is_not_null()
	assert_that(mod.icon_texture).is_not_null()
	assert_that(mod.icon_texture).is_not_equal(PLACEHOLDER)


func test_data_modifier_carries_csv_rarity() -> void:
	# "adrenaline" is Rare in modifiers.csv
	var mod: Modifier = WeaponRegistry._make_modifier("adrenaline")
	assert_that(mod.rarity).is_equal(DropTable.ItemTier.RARE)
