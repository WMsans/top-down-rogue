class_name Modifier
extends Resource

var name: String = "Modifier"
var description: String = ""
var icon_texture: Texture2D = null
var suppresses_base_use: bool = false


func on_equip(_weapon: Weapon) -> void:
	pass


func on_use(_weapon: Weapon, _user: Node) -> void:
	pass


func on_attack(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	pass


func on_tick(_weapon: Weapon, _delta: float) -> void:
	pass


func modify_crit_chance(_weapon: Weapon, base: float) -> float:
	return base


func get_description() -> String:
	return description