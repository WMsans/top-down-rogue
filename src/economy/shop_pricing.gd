# Prices keyed by DropTable.ItemTier. Floor-1 baselines; scaled by price_mult().
class_name ShopPricing

const WEAPON_PRICE := {
	DropTable.ItemTier.COMMON: 130,
	DropTable.ItemTier.UNCOMMON: 220,
	DropTable.ItemTier.RARE: 350,
}
const MODIFIER_PRICE := {
	DropTable.ItemTier.COMMON: 50,
	DropTable.ItemTier.UNCOMMON: 90,
	DropTable.ItemTier.RARE: 150,
}
const REMOVE_BASE := 80
const REMOVE_STEP := 40
const PRICE_FLOOR_COEFF := 0.18


# Floor-depth price multiplier. floor_number <= 0 means "use LevelManager".
static func price_mult(floor_number: int) -> float:
	var n: int = floor_number if floor_number > 0 else LevelManager.floor_number
	return 1.0 + PRICE_FLOOR_COEFF * float(maxi(n, 1) - 1)


static func price_for_weapon(weapon: Weapon, floor_number: int = 0) -> int:
	var base: int = WEAPON_PRICE.get(weapon.rarity, WEAPON_PRICE[DropTable.ItemTier.COMMON])
	return int(round(float(base) * price_mult(floor_number)))


static func price_for_modifier_tier(tier: int, floor_number: int = 0) -> int:
	var base: int = MODIFIER_PRICE.get(tier, MODIFIER_PRICE[DropTable.ItemTier.COMMON])
	return int(round(float(base) * price_mult(floor_number)))


static func remove_cost(uses: int, floor_number: int = 0) -> int:
	return int(round(float(REMOVE_BASE + uses * REMOVE_STEP) * price_mult(floor_number)))


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
