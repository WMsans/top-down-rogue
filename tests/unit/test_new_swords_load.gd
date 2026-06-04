extends GdUnitTestSuite

const IDS := [
	"willowblade", "flame_sword", "frost_sword", "qinggang_sword", "blood_blade",
	"tao_sword", "dragon_fang", "heavenly_sword", "grand_knight_sword", "deep_dark_blade",
	"broadsword", "executioner", "void_sword", "caliburn", "phantom_blade",
]

func test_all_new_swords_resolve() -> void:
	for id in IDS:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_that(w).override_failure_message("weapon '%s' did not load" % id).is_not_null()
		assert_that(w is MeleeWeapon).override_failure_message("'%s' is not MeleeWeapon" % id).is_true()
		assert_str(w.description).is_not_empty()

func test_flame_sword_has_lava_emitter() -> void:
	var w = WeaponRegistry.get_weapon_by_id("flame_sword")
	assert_that(w.get_modifier_at(0)).is_not_null()
	assert_that(w.get_modifier_at(0).name).is_equal("Lava Emitter")

func test_rarities_mapped() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("willowblade").rarity).is_equal(DropTable.ItemTier.COMMON)
	assert_that(WeaponRegistry.get_weapon_by_id("flame_sword").rarity).is_equal(DropTable.ItemTier.UNCOMMON)
	assert_that(WeaponRegistry.get_weapon_by_id("caliburn").rarity).is_equal(DropTable.ItemTier.RARE)
