extends GdUnitTestSuite

const ChestScript = preload("res://src/drops/chest.gd")


func test_chest_gold_range_by_tier() -> void:
	assert_that(Chest.gold_range(DropTable.EnemyTier.NORMAL)).is_equal(Vector2i(25, 40))
	assert_that(Chest.gold_range(DropTable.EnemyTier.HARD)).is_equal(Vector2i(60, 100))


func test_chest_gold_range_defaults_to_normal() -> void:
	assert_that(Chest.gold_range(DropTable.EnemyTier.EASY)).is_equal(Vector2i(25, 40))
