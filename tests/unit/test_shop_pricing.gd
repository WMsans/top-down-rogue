extends GdUnitTestSuite

const ShopPricing = preload("res://src/economy/shop_pricing.gd")


func test_weapon_price_by_rarity() -> void:
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(130)
	w.rarity = DropTable.ItemTier.UNCOMMON
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(220)
	w.rarity = DropTable.ItemTier.RARE
	assert_that(ShopPricing.price_for_weapon(w, 1)).is_equal(350)


func test_modifier_price_by_tier() -> void:
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON, 1)).is_equal(50)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.UNCOMMON, 1)).is_equal(90)
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.RARE, 1)).is_equal(150)


func test_price_scales_with_floor() -> void:
	# price_mult(3) = 1 + 0.18*2 = 1.36
	assert_that(ShopPricing.price_for_modifier_tier(DropTable.ItemTier.COMMON, 3)).is_equal(68)
	var w := Weapon.new()
	w.rarity = DropTable.ItemTier.COMMON
	assert_that(ShopPricing.price_for_weapon(w, 3)).is_equal(177)


func test_remove_cost_escalates_and_scales() -> void:
	assert_that(ShopPricing.remove_cost(0, 1)).is_equal(80)
	assert_that(ShopPricing.remove_cost(1, 1)).is_equal(120)
	assert_that(ShopPricing.remove_cost(2, 1)).is_equal(160)
	assert_that(ShopPricing.remove_cost(0, 3)).is_equal(109)


func test_make_price_label_shows_amount() -> void:
	var label := ShopPricing.make_price_label(42)
	assert_that(label.text).is_equal("42 g")
	assert_that(label.name).is_equal("PriceLabel")
