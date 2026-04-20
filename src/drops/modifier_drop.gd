class_name ModifierDrop
extends Drop

var modifier: Modifier = null


func _ready() -> void:
	super._ready()
	if modifier and modifier.icon_texture:
		_sprite.texture = modifier.icon_texture


func _pickup(player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if not _has_weapon_with_empty_slot(weapon_manager):
		return
	var popup = player.get_parent().get_node("WeaponPopup")
	popup.open_for_modifier(weapon_manager, modifier, _on_modifier_applied)


func _on_modifier_applied() -> void:
	queue_free()


func _has_weapon_with_empty_slot(weapon_manager: WeaponManager) -> bool:
	for weapon in weapon_manager.weapons:
		if weapon != null:
			for i in range(weapon.modifier_slot_count):
				if weapon.get_modifier_at(i) == null:
					return true
	return false