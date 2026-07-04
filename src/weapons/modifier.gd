class_name Modifier
extends Resource

var name: String = "Modifier"
var description: String = ""
var icon_texture: Texture2D = null
var suppresses_base_use: bool = false
var slot_index: int = -1
var category: String = ""
var is_retrigger_modifier: bool = false
var is_disabled: bool = false
var rarity: int = DropTable.ItemTier.COMMON


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


func get_stat_add(_stat: String) -> float:
	return 0.0


func get_stat_mult(_stat: String) -> float:
	return 1.0


func modify_stat(_stat: String, value: float) -> float:
	return value


func modify_hit_damage(_weapon: Weapon, _user: Node, _target: Node, dmg: float) -> float:
	return dmg


func on_hit_target(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass


func on_kill(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass


func on_crit(_weapon: Weapon, _user: Node, _target: Node) -> void:
	pass


func modify_crit_chance_for_target(_weapon: Weapon, base: float, _target: Node) -> float:
	return base


func get_state_tag() -> String:
	if is_disabled:
		return "disabled"
	if is_retrigger_modifier:
		return "retrigger"
	return ""


func get_description() -> String:
	return description