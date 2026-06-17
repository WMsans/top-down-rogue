extends GdUnitTestSuite

func test_all_sp_e_archetype_weapons_build() -> void:
	for id in ["heavy_crossbow", "arc_railgun", "flame_lobber", "venom_spitter",
			"tesla_gun", "chakram_launcher", "seeker_launcher", "hailstorm_bow"]:
		var w: Weapon = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_bucket1_ranged_weapons_build() -> void:
	for id in ["scatter_blunderbuss", "frost_repeater"]:
		var w: Weapon = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).override_failure_message("missing weapon: %s" % id).is_not_null()

func test_frost_repeater_has_freeze_hit_status() -> void:
	var w = WeaponRegistry.get_weapon_by_id("frost_repeater")
	assert_object(w).is_not_null()
	assert_str((w as RangedWeapon).hit_status).is_equal("freeze")
