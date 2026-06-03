# src/economy/shop_pricing.gd
class_name ShopPricing

# Prices keyed by DropTable.ItemTier. Tunable.
const WEAPON_PRICE := {
	DropTable.ItemTier.COMMON: 120,
	DropTable.ItemTier.UNCOMMON: 200,
	DropTable.ItemTier.RARE: 320,
}
const MODIFIER_PRICE := {
	DropTable.ItemTier.COMMON: 30,
	DropTable.ItemTier.UNCOMMON: 60,
	DropTable.ItemTier.RARE: 100,
}
const REMOVE_BASE := 60
const REMOVE_STEP := 30


static func price_for_weapon(weapon: Weapon) -> int:
	return WEAPON_PRICE.get(weapon.rarity, WEAPON_PRICE[DropTable.ItemTier.COMMON])


static func price_for_modifier_tier(tier: int) -> int:
	return MODIFIER_PRICE.get(tier, MODIFIER_PRICE[DropTable.ItemTier.COMMON])


static func make_price_label(price: int) -> Label:
	var label := Label.new()
	label.name = "PriceLabel"
	label.text = "%d g" % price
	label.add_theme_font_size_override("font_size", 16)
	label.position = Vector2(-16, -30)
	label.z_index = 20
	return label


static func refresh_price_color(label: Label, affordable: bool) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if affordable else UiTheme.DANGER)


# Punchy "can't afford" feedback on a world-space sprite + price label.
static func play_reject(sprite: Node2D, label: Label) -> void:
	if sprite != null and sprite.is_inside_tree():
		var t := sprite.create_tween()
		t.tween_property(sprite, "scale", Vector2(1.2, 0.8), 0.06)
		t.tween_property(sprite, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK)
	if label != null and label.is_inside_tree():
		refresh_price_color(label, false)
		var base_x := label.position.x
		var lt := label.create_tween()
		for off in [4.0, -3.0, 2.0, 0.0]:
			lt.tween_property(label, "position:x", base_x + off, 0.04)
