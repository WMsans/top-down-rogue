extends GdUnitTestSuite

func test_all_sp_d_archetype_weapons_build() -> void:
	for id in ["war_scythe", "twin_daggers", "whirlwind_blade", "quake_hammer",
			"mirror_blade", "reaper_glaive", "berserker_axe", "soul_reaver"]:
		var w: Weapon = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_free_carve_weapons_have_flag_set() -> void:
	for id in ["obsidian_greatsword", "gravedigger_spade"]:
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).is_not_null()
		assert_bool((w as MeleeWeapon).free_carve).override_failure_message("free_carve not set on %s" % id).is_true()
