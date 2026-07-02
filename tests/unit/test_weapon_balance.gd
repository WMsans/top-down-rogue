extends GdUnitTestSuite

const CsvTable = preload("res://src/util/csv_table.gd")
const CSV := "res://docs/design_docs/weapons.csv"

# single-target hits-per-activation, keyed by weapon id (default 1.0)
const MULT := {
	"dragon_fang": 3.0, "twin_daggers": 2.0, "chakram_launcher": 2.0,
	"spread_shot": 2.0, "scatter_blunderbuss": 4.0, "hailstorm_bow": 2.5,
}

# [min, max] effective DPS; tolerance is applied below.
const BANDS := {
	"Melee":  {"Common": [5.0, 8.0],  "Uncommon": [7.0, 11.0], "Rare": [9.0, 14.0]},
	"Ranged": {"Uncommon": [5.0, 9.5], "Rare": [7.0, 11.5]},
}
const TOL := 0.6


func test_every_weapon_sits_in_its_rarity_band() -> void:
	var rows: Array = CsvTable.parse(CSV)
	var checked := 0
	for row in rows:
		var id: String = row.get("id", "")
		if id == "":
			continue
		var w = WeaponRegistry.get_weapon_by_id(id)
		assert_object(w).is_not_null()
		var cd: float = w.cooldown
		var dmg: float = w.damage
		var cc: float = w.crit_chance
		var cm: float = w.crit_multiplier
		var crit_factor: float = 1.0 + cc * (cm - 1.0)
		var mult: float = MULT.get(id, 1.0)
		var dps: float = dmg * crit_factor * mult / cd
		var band: Array = BANDS[row["type"]][row["rarity"]]
		assert_float(dps) \
			.override_failure_message("%s (%s %s) DPS=%.1f outside band %s" % [id, row["rarity"], row["type"], dps, str(band)]) \
			.is_between(band[0] - TOL, band[1] + TOL)
		checked += 1
	assert_int(checked).is_equal(51)
