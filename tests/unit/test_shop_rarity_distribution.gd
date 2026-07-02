extends GdUnitTestSuite

const _DropTable = preload("res://src/enemies/drop_table.gd")

const SAMPLES := 5000


func test_modifier_tier_weights_are_60_30_10() -> void:
	var counts := {_DropTable.ItemTier.COMMON: 0, _DropTable.ItemTier.UNCOMMON: 0, _DropTable.ItemTier.RARE: 0}
	for _i in range(SAMPLES):
		var t := _DropTable.roll_modifier_tier()
		counts[t] += 1
	var c: float = float(counts[_DropTable.ItemTier.COMMON]) / SAMPLES
	var u: float = float(counts[_DropTable.ItemTier.UNCOMMON]) / SAMPLES
	var r: float = float(counts[_DropTable.ItemTier.RARE]) / SAMPLES
	assert_float(c).is_between(0.55, 0.65)
	assert_float(u).is_between(0.25, 0.35)
	assert_float(r).is_between(0.07, 0.13)
