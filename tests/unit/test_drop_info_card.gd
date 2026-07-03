extends GdUnitTestSuite

class CardStub extends Card:
	var _populate_icon: Texture2D = null
	var _populate_name: String = ""
	var _populate_stats: Array[String] = []
	var _populate_modifier_icons: Array[Texture2D] = []
	var _called_rarity: int = -2
	var _called_set_rarity: bool = false

	func populate(icon: Texture2D, card_name: String, stats: Array[String] = [], modifier_icons: Array[Texture2D] = []) -> void:
		_populate_icon = icon
		_populate_name = card_name
		_populate_stats = stats
		_populate_modifier_icons = modifier_icons

	func set_rarity(rarity: int) -> void:
		_called_rarity = rarity
		_called_set_rarity = true


func test_drop_populate_info_card_is_noop() -> void:
	var drop: Drop = auto_free(Drop.new())
	var stub: Card = auto_free(CardStub.new())
	drop.populate_info_card(stub)
	assert_that(stub._populate_name).is_empty()
	assert_that(stub._called_set_rarity).is_false()


func test_weapon_drop_populate_info_card() -> void:
	var drop: WeaponDrop = auto_free(WeaponDrop.new())
	var weapon := Weapon.new()
	weapon.name = "Sword"
	weapon.damage = 15.0
	weapon.cooldown = 0.8
	weapon.crit_chance = 0.1
	weapon.crit_multiplier = 2.5
	weapon.rarity = DropTable.ItemTier.RARE
	drop.weapon = weapon

	var stub: Card = auto_free(CardStub.new())
	drop.populate_info_card(stub)

	assert_that(stub._populate_name).is_equal("Sword")
	assert_that(stub._populate_stats).contains(["Damage: 15"])
	assert_that(stub._populate_stats).contains(["Cooldown: 0.8s"])
	assert_that(stub._populate_stats).contains(["Crit: 10%"])
	assert_that(stub._populate_stats).contains(["Crit Mult: 2.5x"])
	assert_that(stub._called_set_rarity).is_true()
	assert_that(stub._called_rarity).is_equal(DropTable.ItemTier.RARE)


func test_modifier_drop_populate_info_card() -> void:
	var drop: ModifierDrop = auto_free(ModifierDrop.new())
	var mod := Modifier.new()
	mod.name = "Fire Mod"
	mod.description = "Adds fire damage"
	mod.rarity = DropTable.ItemTier.UNCOMMON
	drop.modifier = mod

	var stub: Card = auto_free(CardStub.new())
	drop.populate_info_card(stub)

	assert_that(stub._populate_name).is_equal("Fire Mod")
	assert_that(stub._populate_stats).contains(["Adds fire damage"])
	assert_that(stub._populate_modifier_icons).is_empty()
	assert_that(stub._called_set_rarity).is_true()
	assert_that(stub._called_rarity).is_equal(DropTable.ItemTier.UNCOMMON)
