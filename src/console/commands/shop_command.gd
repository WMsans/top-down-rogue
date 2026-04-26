extends RefCounted

const SHOP_UI_SCENE := preload("res://scenes/economy/shop_ui.tscn")
const ShopOfferScript := preload("res://src/economy/shop_offer.gd")


static func register(registry: CommandRegistry) -> void:
	registry.register("shop", "Open the test shop", _shop)


static func _shop(_args: Array[String], ctx: Dictionary) -> String:
	var player := ctx.get("player")
	if player == null:
		return "error: no player found"
	var scene := ctx.get("scene")
	if scene == null:
		return "error: no scene available"
	var shop: ShopUI = SHOP_UI_SCENE.instantiate()
	scene.add_child(shop)

	var offerings: Array[ShopOffer] = []
	var mod_keys := WeaponRegistry.modifier_scripts.keys()
	var prices: Array[int] = [35, 55, 80]
	prices.shuffle()
	for i in min(mod_keys.size(), 3):
		var script: GDScript = WeaponRegistry.modifier_scripts[mod_keys[i]]
		offerings.append(ShopOfferScript.new(script.new(), prices[i]))
	shop.open(offerings)
	return "Opened test shop"
