class_name WeaponDrop
extends Drop

var weapon: Weapon = null


func get_pickup_type() -> int:
	return Drop.PickupType.WEAPON

func get_pickup_payload():
	return weapon


func _ready() -> void:
	super._ready()
	if weapon and weapon.icon_texture:
		_sprite.texture = weapon.icon_texture


func _pickup(player: Node) -> void:
	var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
	if delivery == null:
		return
	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.WEAPON
	spec.weapon = weapon
	delivery.offer(spec, _on_delivery_result)


func _on_delivery_result(accepted: bool, _slot: int) -> void:
	if accepted:
		queue_free()
