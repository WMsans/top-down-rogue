extends GdUnitTestSuite

const ChestScript = preload("res://src/drops/chest.gd")


func test_chest_can_roll_all_weapon_classes() -> void:
	var saw_melee := false
	var saw_ranged := false
	for _i in range(500):
		var chest: Chest = ChestScript.new()
		chest.tier = DropTable.EnemyTier.HARD
		chest._generate_weapons()
		for weapon in chest._weapons:
			if weapon is MeleeWeapon:
				saw_melee = true
			elif weapon is RangedWeapon:
				saw_ranged = true
		if saw_melee and saw_ranged:
			break
	assert_that(saw_melee).is_true()
	assert_that(saw_ranged).is_true()


func test_chest_default_tier_is_enemy_tier_normal() -> void:
	var chest: Chest = ChestScript.new()
	assert_that(chest.tier).is_equal(DropTable.EnemyTier.NORMAL)
