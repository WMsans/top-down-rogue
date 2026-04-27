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
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
	if not _has_weapon_with_empty_slot(inventory):
		var weapon_button := player.get_parent().get_node_or_null("WeaponButton")
		if weapon_button != null:
			weapon_button.flash_slots_full()
		else:
			push_warning("ModifierDrop: WeaponButton not found in scene tree")
		return
	var popup = player.get_parent().get_node("WeaponPopup")
	popup.open_for_modifier(weapon_manager, modifier, _on_modifier_applied)


func _on_modifier_applied() -> void:
	queue_free()


func _has_weapon_with_empty_slot(inventory: PlayerInventory) -> bool:
	if not inventory:
		return false
	for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
		var weapon = inventory.get_weapon(i)
		if weapon != null:
			for j in range(weapon.modifier_slot_count):
				if weapon.get_modifier_at(j) == null:
					return true
	return false