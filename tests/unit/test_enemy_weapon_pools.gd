extends GdUnitTestSuite


func test_skirmisher_pool_contains_fast_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("skirmisher")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("bone_dagger")).is_true()


func test_skirmisher_pool_excludes_slow_heavy_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("skirmisher")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("broad_axe")).is_false()


func test_brute_pool_contains_slow_heavy_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("brute")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("broad_axe")).is_true()


func test_armored_pool_contains_long_reach_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("armored")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("war_scythe")).is_true()


func test_cultist_pool_contains_weak_weapon() -> void:
	var pool := EnemyWeaponPools.build_melee_pool("cultist")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("bone_dagger")).is_true()


func test_every_melee_weapon_lands_in_at_least_one_pool() -> void:
	var all_ids: Array = []
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		if row.get("type", "") == "Melee":
			all_ids.append(row.get("id", ""))
	var covered: Dictionary = {}
	for archetype in ["grunt", "brute", "skirmisher", "armored", "cultist"]:
		for entry in EnemyWeaponPools.build_melee_pool(archetype):
			covered[entry["id"]] = true
	for id in all_ids:
		assert_bool(covered.has(id)).is_true()


func test_mage_pool_contains_seeker_launcher() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("mage")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("seeker_launcher")).is_true()


func test_lobber_pool_contains_flame_lobber() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("lobber")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("flame_lobber")).is_true()


func test_archer_pool_contains_throwing_knife() -> void:
	var pool := EnemyWeaponPools.build_ranged_pool("archer")
	var ids: Array = pool.map(func(e): return e["id"])
	assert_bool(ids.has("throwing_knife")).is_true()


func test_ranged_pools_exclude_boss_staff() -> void:
	for archetype in ["archer", "mage", "lobber"]:
		var pool := EnemyWeaponPools.build_ranged_pool(archetype)
		var ids: Array = pool.map(func(e): return e["id"])
		assert_bool(ids.has("boss_staff")).is_false()


func test_ranged_pool_ids_resolve_via_weapon_registry() -> void:
	for archetype in ["archer", "mage", "lobber"]:
		for entry in EnemyWeaponPools.build_ranged_pool(archetype):
			var w := WeaponRegistry.get_weapon_by_id(entry["id"])
			assert_object(w).is_not_null()


func test_base_weights_floor_1_is_common_heavy() -> void:
	var w := EnemyWeaponPools.base_weights_for_floor(1)
	assert_float(w["Common"]).is_equal_approx(0.85, 0.001)
	assert_float(w["Uncommon"]).is_equal_approx(0.15, 0.001)
	assert_float(w["Rare"]).is_equal_approx(0.0, 0.001)


func test_base_weights_floor_5_unlocks_rare() -> void:
	var w := EnemyWeaponPools.base_weights_for_floor(5)
	assert_float(w["Common"]).is_equal_approx(0.50, 0.001)
	assert_float(w["Uncommon"]).is_equal_approx(0.35, 0.001)
	assert_float(w["Rare"]).is_equal_approx(0.15, 0.001)


func test_rarity_weights_sum_to_one() -> void:
	var w := EnemyWeaponPools.rarity_weights(5, 4, DropTable.EnemyTier.HARD)
	var total: float = w["Common"] + w["Uncommon"] + w["Rare"]
	assert_float(total).is_equal_approx(1.0, 0.001)


func test_kill_streak_shifts_weight_toward_rare() -> void:
	var base := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.EASY)
	var boosted := EnemyWeaponPools.rarity_weights(1, 4, DropTable.EnemyTier.EASY)
	assert_float(boosted["Rare"]).is_greater(base["Rare"])


func test_hard_sector_tier_shifts_weight_toward_rare() -> void:
	var easy := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.EASY)
	var hard := EnemyWeaponPools.rarity_weights(1, 0, DropTable.EnemyTier.HARD)
	assert_float(hard["Rare"]).is_greater(easy["Rare"])


func test_pick_weapon_id_returns_empty_for_empty_pool() -> void:
	var id := EnemyWeaponPools.pick_weapon_id([], 1, 0, DropTable.EnemyTier.EASY)
	assert_str(id).is_equal("")


func test_pick_weapon_id_returns_id_from_pool() -> void:
	var pool: Array[Dictionary] = [{"id": "only_option", "rarity": "Common"}]
	var id := EnemyWeaponPools.pick_weapon_id(pool, 1, 0, DropTable.EnemyTier.EASY)
	assert_str(id).is_equal("only_option")
