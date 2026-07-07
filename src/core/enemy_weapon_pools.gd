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
