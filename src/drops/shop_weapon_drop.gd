class_name ShopWeaponDrop
extends WeaponDrop

var price: int = 0
var _price_label: Label = null


func _ready() -> void:
	super._ready()
	_price_label = ShopPricing.make_price_label(price)
	add_child(_price_label)
	_refresh_affordability()


func _process(_delta: float) -> void:
	_refresh_affordability()


func _refresh_affordability() -> void:
	if _price_label == null:
		return
	ShopPricing.refresh_price_color(_price_label, _player_gold() >= price)


func _player_gold() -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var inv: PlayerInventory = player.get_node_or_null("PlayerInventory")
		if inv:
			return inv.gold
	return 0


func _pickup(_player: Node) -> void:
	var inventory: PlayerInventory = _player.get_node_or_null("PlayerInventory")
	if inventory == null:
		return
	if inventory.gold < price:
		ShopPricing.play_reject(_sprite, _price_label)
		return
	var delivery: WeaponDelivery = _player.get_node_or_null("WeaponDelivery")
	if delivery == null:
		return
	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = weapon
	var price_ref := price
	delivery.offer(spec, func(accepted: bool, _slot: int) -> void:
		if not accepted:
			return
		inventory.spend_gold(price_ref)
		queue_free()
	)
