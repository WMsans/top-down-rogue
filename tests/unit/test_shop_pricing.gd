extends GdUnitTestSuite

const ShopPricing = preload("res://src/economy/shop_pricing.gd")


func test_weapon_price_by_rarity() -> void:
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	assert_that(ShopPricing.price_for_weapon(w)).is_equal(120)
	w.rarity = DropTable.ItemTier.UNCOMMON
	assert_that(ShopPricing.price_for_weapon(w)).is_equal(200)
	w.rarity = DropTable.ItemTier.RARE
	assert_that(ShopPricing.price_for_weapon(w)).is_equal(320)


func test_modifier_price_by_tier() -> void:
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON)).is_equal(30)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.UNCOMMON)).is_equal(60)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.RARE)).is_equal(100)


func test_make_price_label_shows_amount() -> void:
	var label := ShopPricing.make_price_label(42)
	assert_that(label.text).is_equal("42 g")
	assert_that(label.name).is_equal("PriceLabel")
