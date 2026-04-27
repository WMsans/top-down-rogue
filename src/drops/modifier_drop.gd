class_name ModifierDrop
extends Drop

var modifier: Modifier = null


func get_pickup_type() -> int:
	return Drop.PickupType.MODIFIER

func get_pickup_payload():
	return modifier


func _ready() -> void:
	super._ready()
	if modifier and modifier.icon_texture:
		_sprite.texture = modifier.icon_texture


func _pickup(player: Node) -> void:
	var delivery: WeaponDelivery = player.get_node_or_null("WeaponDelivery")
	if delivery == null:
		return
	var spec := WeaponOfferSpec.new()
	spec.type = WeaponOfferSpec.OfferType.MODIFIER
	spec.modifier = modifier
	spec.suggested_slot = 0
	delivery.offer(spec, _on_delivery_result)


func _on_delivery_result(accepted: bool, _slot: int) -> void:
	if accepted:
		queue_free()
