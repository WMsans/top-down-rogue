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
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	var popup = player.get_parent().get_node("WeaponPopup")
	popup.open_for_pickup(weapon_manager, weapon, _on_slot_selected.bind(player))


func _on_slot_selected(slot_index: int, modifier: Modifier, player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if modifier != null:
		var empty_slot := weapon.find_empty_modifier_slot()
		if empty_slot >= 0:
			weapon.add_modifier(empty_slot, modifier)
		else:
			weapon.add_modifier(0, modifier)
	var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
	if inventory:
		inventory.equip_weapon(slot_index, weapon)
	queue_free()
