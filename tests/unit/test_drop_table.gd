extends GdUnitTestSuite

const _DropTable = preload("res://src/enemies/drop_table.gd")


func test_drop_entry_gold_constructor() -> void:
	var entry := _DropTable.DropEntry.gold(0.8, 2, 5, 10)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.GOLD)
	assert_that(entry.weight).is_equal(0.8)
	assert_that(entry.min_count).is_equal(2)
	assert_that(entry.max_count).is_equal(5)
	assert_that(entry.gold_per_drop).is_equal(10)


func test_drop_entry_weapon_pool_constructor() -> void:
	var entry := _DropTable.DropEntry.weapon_pool(0.3, _DropTable.ItemTier.UNCOMMON)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.WEAPON_POOL)
	assert_that(entry.weight).is_equal(0.3)
	assert_that(entry.item_tier).is_equal(_DropTable.ItemTier.UNCOMMON)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(1)


func test_drop_entry_modifier_pool_constructor() -> void:
	var entry := _DropTable.DropEntry.modifier_pool(0.15, _DropTable.ItemTier.RARE, 1, 2)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.MODIFIER_POOL)
	assert_that(entry.weight).is_equal(0.15)
	assert_that(entry.item_tier).is_equal(_DropTable.ItemTier.RARE)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(2)


func test_drop_entry_from_scene_constructor() -> void:
	var entry := _DropTable.DropEntry.from_scene(null, 0.5, 1, 3)
	assert_that(entry.kind).is_equal(_DropTable.DropKind.SCENE)
	assert_that(entry.weight).is_equal(0.5)
	assert_that(entry.min_count).is_equal(1)
	assert_that(entry.max_count).is_equal(3)
	assert_that(entry.packed_scene).is_null()


func test_from_enemy_tier_creates_table_for_easy() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY)
	assert_that(table.entries.size()).is_equal(7)


func test_from_enemy_tier_creates_table_for_hard() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.HARD)
	assert_that(table.entries.size()).is_equal(7)


func test_from_enemy_tier_gold_only() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.NORMAL, true, false, false)
	assert_that(table.entries.size()).is_equal(1)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.GOLD)


func test_from_enemy_tier_weapon_entries_exist() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY, false, true, false)
	assert_that(table.entries.size()).is_equal(3)
	assert_that(table.entries[0].kind).is_equal(_DropTable.DropKind.WEAPON_POOL)
	assert_that(table.entries[0].item_tier).is_equal(_DropTable.ItemTier.COMMON)


func test_resolve_item_tier_returns_valid_tier() -> void:
	var tier := _DropTable.resolve_item_tier(_DropTable.EnemyTier.NORMAL)
	assert_that(tier >= _DropTable.ItemTier.COMMON).is_true()
	assert_that(tier <= _DropTable.ItemTier.RARE).is_true()


func test_add_entry_and_entries_count() -> void:
	var table := _DropTable.new()
	table.add_entry(_DropTable.DropEntry.gold(1.0, 1, 3, 5))
	table.add_entry(_DropTable.DropEntry.weapon_pool(0.3, _DropTable.ItemTier.COMMON))
	assert_that(table.entries.size()).is_equal(2)


func test_from_enemy_tier_gold_amounts_easy() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.EASY, true, false, false)
	assert_that(table.entries.size()).is_equal(1)
	var entry: _DropTable.DropEntry = table.entries[0]
	assert_that(entry.kind).is_equal(_DropTable.DropKind.GOLD)
	assert_that(entry.min_count).is_equal(2)
	assert_that(entry.max_count).is_equal(5)
	assert_that(entry.gold_per_drop).is_equal(5)


func test_from_enemy_tier_gold_amounts_hard() -> void:
	var table := _DropTable.from_enemy_tier(_DropTable.EnemyTier.HARD, true, false, false)
	var entry: _DropTable.DropEntry = table.entries[0]
	assert_that(entry.min_count).is_equal(8)
	assert_that(entry.max_count).is_equal(20)