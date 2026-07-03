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


func populate_info_card(card: Card) -> void:
	var stats: Array[String] = []
	var mod_icons: Array[Texture2D] = []
	if weapon:
		stats.append("Damage: %.0f" % weapon.damage)
		stats.append("Cooldown: %.1fs" % weapon.cooldown)
		if weapon.crit_chance > 0.0:
			stats.append("Crit: %.0f%%" % (weapon.crit_chance * 100.0))
		if weapon.crit_multiplier != 2.0:
			stats.append("Crit Mult: %.1fx" % weapon.crit_multiplier)
		for mod in weapon.modifiers:
			if mod != null and mod.icon_texture:
				mod_icons.append(mod.icon_texture)
			elif mod != null:
				mod_icons.append(null)
	card.populate(weapon.icon_texture if weapon else null, weapon.name if weapon else "", stats, mod_icons)
	if weapon:
		card.set_rarity(weapon.rarity)
