class_name EnemyWeaponPools
extends RefCounted


static func melee_weapon_fits(row: Dictionary, archetype: String) -> bool:
	var cooldown: float = float(row.get("cooldown", "0"))
	var damage: float = float(row.get("damage", "0"))
	var reach: float = float(row.get("reach", "0"))
	match archetype:
		"skirmisher":
			return cooldown <= 0.40
		"grunt":
			return cooldown >= 0.40 and cooldown <= 0.60 and reach >= 26.0 and reach <= 34.0
		"brute":
			return cooldown >= 0.60 or damage >= 6.0
		"armored":
			return reach >= 34.0
		"cultist":
			return damage <= 3.0
	return false


static func build_melee_pool(archetype: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		if row.get("type", "") != "Melee":
			continue
		var id: String = row.get("id", "")
		if id == "":
			continue
		if melee_weapon_fits(row, archetype):
			pool.append({"id": id, "rarity": row.get("rarity", "Common")})
	return pool


const RANGED_POOL_IDS := {
	"archer": ["throwing_knife", "frost_repeater", "heavy_crossbow", "spread_shot", "scatter_blunderbuss", "tesla_gun", "arc_railgun", "chakram_launcher"],
	"mage": ["seeker_launcher", "fire_orb"],
	"lobber": ["flame_lobber", "venom_spitter", "hailstorm_bow"],
}


static func build_ranged_pool(archetype: String) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	var ids: Array = RANGED_POOL_IDS.get(archetype, [])
	if ids.is_empty():
		return pool
	var rarity_by_id: Dictionary = {}
	for row in CsvTable.parse(WeaponRegistry.WEAPON_CSV_PATH):
		rarity_by_id[row.get("id", "")] = row.get("rarity", "Common")
	for id in ids:
		pool.append({"id": id, "rarity": rarity_by_id.get(id, "Common")})
	return pool


const FLOOR_BASE_WEIGHTS: Array[Dictionary] = [
	{"max_floor": 2, "weights": {"Common": 0.85, "Uncommon": 0.15, "Rare": 0.0}},
	{"max_floor": 4, "weights": {"Common": 0.65, "Uncommon": 0.30, "Rare": 0.05}},
	{"max_floor": 999, "weights": {"Common": 0.50, "Uncommon": 0.35, "Rare": 0.15}},
]


static func base_weights_for_floor(floor_num: int) -> Dictionary:
	for band in FLOOR_BASE_WEIGHTS:
		if floor_num <= band["max_floor"]:
			return band["weights"].duplicate()
	return FLOOR_BASE_WEIGHTS[-1]["weights"].duplicate()


static func rarity_weights(floor_num: int, kill_streak: int, sector_tier: int) -> Dictionary:
	var w: Dictionary = base_weights_for_floor(floor_num)
	var rare_bonus := 0.0
	var uncommon_bonus := 0.0
	if kill_streak > 0:
		rare_bonus += float(kill_streak) * 0.02
		uncommon_bonus += float(kill_streak) * 0.01
	if sector_tier == DropTable.EnemyTier.HARD:
		rare_bonus += 0.10
		uncommon_bonus += 0.05
	elif sector_tier == DropTable.EnemyTier.NORMAL:
		rare_bonus += 0.05
		uncommon_bonus += 0.03
	w["Rare"] = w["Rare"] + rare_bonus
	w["Uncommon"] = w["Uncommon"] + uncommon_bonus
	w["Common"] = maxf(0.0, w["Common"] - rare_bonus - uncommon_bonus)
	var total: float = w["Common"] + w["Uncommon"] + w["Rare"]
	if total <= 0.0:
		return {"Common": 1.0, "Uncommon": 0.0, "Rare": 0.0}
	w["Common"] /= total
	w["Uncommon"] /= total
	w["Rare"] /= total
	return w


static func roll_rarity_tier(weights: Dictionary) -> String:
	var roll := randf()
	var cumulative := 0.0
	for tier in ["Common", "Uncommon", "Rare"]:
		cumulative += float(weights.get(tier, 0.0))
		if roll <= cumulative:
			return tier
	return "Common"


static func pick_weapon_id(pool: Array[Dictionary], floor_num: int, kill_streak: int, sector_tier: int) -> String:
	if pool.is_empty():
		return ""
	var weights := rarity_weights(floor_num, kill_streak, sector_tier)
	var tier := roll_rarity_tier(weights)
	var candidates: Array[Dictionary] = pool.filter(func(e): return e["rarity"] == tier)
	if candidates.is_empty():
		candidates = pool.filter(func(e): return e["rarity"] == "Common")
	if candidates.is_empty():
		candidates = pool
	return candidates[randi() % candidates.size()]["id"]
