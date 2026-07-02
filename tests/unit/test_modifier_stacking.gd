extends GdUnitTestSuite

const DataModifier = preload("res://src/weapons/modifiers/data_modifier.gd")
const Weapon = preload("res://src/weapons/weapon.gd")

func _mod(id: String) -> DataModifier:
	for row in CsvTable.parse("res://docs/design_docs/modifiers.csv"):
		if row.get("id", "") == id:
			return DataModifier.new(row)
	return null

func _weapon_with(ids: Array) -> Weapon:
	var w := Weapon.new()
	w.cooldown = 0.2
	w.crit_chance = 0.0
	w.modifier_slot_count = 3
	w.modifiers = []
	for id in ids:
		w.modifiers.append(_mod(id))
	w.invalidate_effective_stats()
	return w

func test_cooldown_cannot_drop_below_floor() -> void:
	var w := _weapon_with(["adrenaline", "quickdraw"])
	assert_float(w.get_effective_stats()["cooldown"]).is_equal(0.1)

func test_crit_chance_clamped_to_one() -> void:
	var w := _weapon_with(["honed_point"])
	w.crit_chance = 0.95
	w.invalidate_effective_stats()
	assert_float(w.get_effective_crit_chance()).is_equal(1.0)

func test_additive_then_multiplicative_order() -> void:
	var w := _weapon_with(["sharpened", "heavy_head"])
	w.damage = 10.0
	w.invalidate_effective_stats()
	assert_float(w.get_effective_stats()["damage"]).is_equal(18.0)
