class_name Modifier
extends RefCounted

var name: String = "Modifier"
var description: String = ""
var icon_texture: Texture2D = null
var suppresses_base_use: bool = false


func on_equip(_weapon: Weapon) -> void:
	pass


func on_use(_weapon: Weapon, _user: Node) -> void:
	pass


func on_tick(_weapon: Weapon, _delta: float) -> void:
	pass


func get_description() -> String:
	return description