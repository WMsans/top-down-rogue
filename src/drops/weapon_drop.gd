class_name WeaponDrop
extends Drop

var weapon: Weapon = null


func _ready() -> void:
	super._ready()
	if weapon and weapon.icon_texture:
		_sprite.texture = weapon.icon_texture


func _pickup(player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	if weapon_manager.try_add_weapon(weapon):
		queue_free()
	else:
		var popup = player.get_parent().get_node("WeaponPopup")
		popup.open_for_pickup(weapon_manager, weapon, _on_slot_selected.bind(player))


func _on_slot_selected(slot_index: int, player: Node) -> void:
	var weapon_manager: WeaponManager = player.get_node("WeaponManager")
	var old_weapon: Weapon = weapon_manager.swap_weapon(slot_index, weapon)
	if old_weapon:
		var drop_scene: PackedScene = preload("res://scenes/weapon_drop.tscn")
		var new_drop: WeaponDrop = drop_scene.instantiate()
		new_drop.weapon = old_weapon
		player.get_parent().add_child(new_drop)
		new_drop.global_position = player.global_position
	queue_free()