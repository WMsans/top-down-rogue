extends GdUnitTestSuite


func test_get_random_weapon_common_returns_weapon() -> void:
	var weapon := WeaponRegistry.get_random_weapon(DropTable.ItemTier.COMMON)
	assert_that(weapon).is_not_null()
	assert_that(weapon is Weapon).is_true()


func test_get_random_weapon_fallback_to_common() -> void:
	var weapon := WeaponRegistry.get_random_weapon(DropTable.ItemTier.RARE)
	assert_that(weapon).is_not_null()
	assert_that(weapon is Weapon).is_true()


func test_get_random_modifier_common_returns_modifier() -> void:
	var modifier := WeaponRegistry.get_random_modifier(DropTable.ItemTier.COMMON)
	assert_that(modifier).is_not_null()
	assert_that(modifier is Modifier).is_true()


func test_get_random_modifier_fallback_to_common() -> void:
	var modifier := WeaponRegistry.get_random_modifier(DropTable.ItemTier.RARE)
	assert_that(modifier).is_not_null()
	assert_that(modifier is Modifier).is_true()


func test_weapon_tiers_populated() -> void:
	assert_that(WeaponRegistry.weapon_tiers.has(DropTable.ItemTier.COMMON)).is_true()
	var common_entries: Array = WeaponRegistry.weapon_tiers[DropTable.ItemTier.COMMON]
	assert_that(common_entries.size() > 0).is_true()


func test_modifier_tiers_populated() -> void:
	assert_that(WeaponRegistry.modifier_tiers.has(DropTable.ItemTier.COMMON)).is_true()
	var common_entries: Array = WeaponRegistry.modifier_tiers[DropTable.ItemTier.COMMON]
	assert_that(common_entries.size() > 0).is_true()


func test_get_random_weapon_uncommon_fallback() -> void:
	var weapon := WeaponRegistry.get_random_weapon(DropTable.ItemTier.UNCOMMON)
	assert_that(weapon).is_not_null()
	assert_that(weapon is Weapon).is_true()


func test_get_random_modifier_uncommon_fallback() -> void:
	var modifier := WeaponRegistry.get_random_modifier(DropTable.ItemTier.UNCOMMON)
	assert_that(modifier).is_not_null()
	assert_that(modifier is Modifier).is_true()