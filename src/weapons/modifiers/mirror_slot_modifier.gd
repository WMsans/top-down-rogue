class_name MirrorSlotModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	name = "Mirror Slot"
	description = "Become a copy of the modifier to your left."


func _left(weapon: Weapon) -> Modifier:
	var left: Modifier = weapon.get_left_modifier(slot_index)
	if left == null or left is MirrorSlotModifier:
		return null
	return left


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_attack(weapon, user, ctx)


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_hit_target(weapon, user, target)


func modify_hit_damage(weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var l: Modifier = _left(weapon)
	if l != null:
		return l.modify_hit_damage(weapon, user, target, dmg)
	return dmg


func on_kill(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var l: Modifier = _left(weapon)
	if l != null:
		l.on_kill(weapon, user, target)


func get_stat_add(stat: String) -> float:
	var l: Modifier = _left_of_self()
	if l != null:
		return l.get_stat_add(stat)
	return 0.0


func get_stat_mult(stat: String) -> float:
	var l: Modifier = _left_of_self()
	if l != null:
		return l.get_stat_mult(stat)
	return 1.0


func _left_of_self() -> Modifier:
	return _cached_left


var _cached_left: Modifier = null


func on_equip(weapon: Weapon) -> void:
	_cached_left = weapon.get_left_modifier(slot_index)
	if _cached_left != null and _cached_left is MirrorSlotModifier:
		_cached_left = null
