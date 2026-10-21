extends GdUnitTestSuite

const ALL_WEAPON_IDS := [
	"rusty_sword", "bone_dagger", "broad_axe", "flame_blade", "throwing_knife", "fire_orb",
	"spread_shot", "boss_staff", "willowblade", "flame_sword", "frost_sword", "qinggang_sword",
	"blood_blade", "tao_sword", "dragon_fang", "heavenly_sword", "grand_knight_sword",
	"deep_dark_blade", "broadsword", "executioner", "void_sword", "caliburn", "phantom_blade",
	"iron_mace", "rapier", "cleaver", "war_scythe", "twin_daggers", "obsidian_greatsword",
	"venom_fang_blade", "tide_caller", "cinder_brand", "glacier_edge", "thunder_katana",
	"gravedigger_spade", "reaper_glaive", "berserker_axe", "mirror_blade", "whirlwind_blade",
	"quake_hammer", "soul_reaver", "heavy_crossbow", "scatter_blunderbuss", "arc_railgun",
	"flame_lobber", "frost_repeater", "venom_spitter", "tesla_gun", "chakram_launcher",
	"seeker_launcher", "hailstorm_bow",
]

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
	assert_that(w.dig_power).is_equal(3.0)
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

func test_crit_status_weapons_now_use_hit_status() -> void:
	assert_str(WeaponRegistry.get_weapon_by_id("flame_sword").hit_status).is_equal("on_fire")
	assert_str(WeaponRegistry.get_weapon_by_id("frost_sword").hit_status).is_equal("chilly")
	assert_str(WeaponRegistry.get_weapon_by_id("tide_caller").hit_status).is_equal("wet")

func test_weapons_have_no_crit_fields() -> void:
	var w = WeaponRegistry.get_weapon_by_id("caliburn")
	assert_bool("crit_chance" in w).is_false()
	assert_bool("crit_multiplier" in w).is_false()
	assert_bool("crit_status" in w).is_false()

func test_every_weapon_has_dig_power() -> void:
	for id in ALL_WEAPON_IDS:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_that(w).override_failure_message("missing weapon '%s'" % id).is_not_null()
		assert_float(w.dig_power).override_failure_message("'%s' dig_power" % id).is_greater(0.0)
		assert_bool("damage" in w).override_failure_message("'%s' still has damage" % id).is_false()

func test_dig_power_by_archetype() -> void:
	assert_float(WeaponRegistry.get_weapon_by_id("bone_dagger").dig_power).is_equal(1.5)
	assert_float(WeaponRegistry.get_weapon_by_id("rusty_sword").dig_power).is_equal(3.0)
	assert_float(WeaponRegistry.get_weapon_by_id("iron_mace").dig_power).is_equal(5.0)
	assert_float(WeaponRegistry.get_weapon_by_id("quake_hammer").dig_power).is_equal(7.0)
	assert_float(WeaponRegistry.get_weapon_by_id("gravedigger_spade").dig_power).is_equal(9.0)
	assert_float(WeaponRegistry.get_weapon_by_id("heavy_crossbow").dig_power).is_equal(2.0)

func test_sharpened_adds_dig_power() -> void:
	var w = WeaponRegistry.get_weapon_by_id("rusty_sword")
	w.add_modifier(w.find_empty_modifier_slot(), WeaponRegistry._make_modifier("sharpened"))
	assert_float(w.get_effective_stats()["dig_power"]).is_equal_approx(6.0, 0.001)
