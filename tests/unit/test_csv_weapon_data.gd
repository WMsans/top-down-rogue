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


func test_weapon_universal_fields_from_csv() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w).is_not_null()
	assert_that(w.name).is_equal("Rusty Sword")
	assert_that(w.damage).is_equal(3.0)
	assert_that(w.cooldown).is_equal(0.5)

func test_weapon_keeps_type_specific_tres_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	assert_that(w.weapon_reach).is_equal(28.0)

func test_rarity_word_mapped_to_enum() -> void:
	var w = WeaponRegistry.get_weapon_by_id("boss_staff")
	assert_that(w.rarity).is_equal(DropTable.ItemTier.RARE)

func test_pre_attached_modifier_applied() -> void:
	var w = WeaponRegistry.get_weapon_by_id("flame_blade")
	var mod = w.get_modifier_at(0)
	assert_that(mod).is_not_null()
	assert_that(mod.name).is_equal("Lava Emitter")

func test_unknown_weapon_id_returns_null() -> void:
	assert_that(WeaponRegistry.get_weapon_by_id("nope")).is_null()

func test_make_modifier_builds_data_modifier_for_new_id() -> void:
	var m = WeaponRegistry._make_modifier("oil_emitter")
	assert_that(m).is_not_null()
	assert_that(m is DataModifier).is_true()
	assert_str(m.name).is_equal("Oil Emitter")
	assert_str(m.element).is_equal("oil")

func test_bespoke_modifier_still_scripted() -> void:
	var m = WeaponRegistry._make_modifier("lava_emitter")
	assert_that(m is DataModifier).is_false()

func test_new_modifier_is_droppable() -> void:
	var total := 0
	for tier in WeaponRegistry.modifier_tiers.keys():
		total += WeaponRegistry.modifier_tiers[tier].size()
	assert_int(total).is_greater_equal(50)
