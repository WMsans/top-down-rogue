class_name ShopRemoval
extends Area2D

var _uses: int = 0
var _price_label: Label = null

@onready var _sprite: Sprite2D = $Sprite2D


func get_pickup_type() -> int:
	return Drop.PickupType.MODIFIER


func get_pickup_payload():
	return null


func should_auto_pickup() -> bool:
	return false


func _ready() -> void:
	_price_label = ShopPricing.make_price_label(_current_cost())
	add_child(_price_label)


func _process(_delta: float) -> void:
	if _price_label != null:
		ShopPricing.refresh_price_color(_price_label, _player_gold() >= _current_cost())


func _current_cost() -> int:
	return ShopPricing.REMOVE_BASE + _uses * ShopPricing.REMOVE_STEP


func _player_gold() -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var inv: PlayerInventory = player.get_node_or_null("PlayerInventory")
		if inv:
			return inv.gold
	return 0


func interact(player: Node) -> void:
	var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
	if inventory == null:
		return
	if not _has_equipped_modifier(inventory) or inventory.gold < _current_cost():
		ShopPricing.play_reject(_sprite, _price_label)
		return
	var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
	if delivery == null:
		return
	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.REMOVE_MODIFIER
	var cost := _current_cost()
	delivery.offer(spec, func(accepted: bool, _slot: int) -> void:
		if not accepted:
			return
		inventory.spend_gold(cost)
		_uses += 1
		if _price_label != null:
			_price_label.text = "%d g" % _current_cost()
	)


func _has_equipped_modifier(inventory: PlayerInventory) -> bool:
	for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
		var weapon = inventory.get_weapon(i)
		if weapon == null:
			continue
		for m in weapon.modifiers:
			if m != null:
				return true
	return false


func set_highlighted(enabled: bool) -> void:
	if _sprite and _sprite.material is ShaderMaterial:
		(_sprite.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)
