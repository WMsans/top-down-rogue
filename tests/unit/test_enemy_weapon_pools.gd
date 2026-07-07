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
