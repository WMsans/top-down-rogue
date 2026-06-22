extends GdUnitTestSuite


func test_boss_drop_table_includes_bonus_gold() -> void:
	var boss := BossEnemy.new()
	auto_free(boss)
	boss._setup_drop_table()
	var bonus := boss.drop_table.entries.filter(func(e):
		return e.kind == DropTable.DropKind.GOLD and e.gold_per_drop == 10)
	assert_int(bonus.size()).is_equal(1)
	assert_int(bonus[0].min_count).is_equal(5)
	assert_int(bonus[0].max_count).is_equal(8)
