class_name PendulumModifier
extends Modifier

var _swings: int = 0


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Pendulum"
	description = "Odd swings ×2 your left modifier, even swings ×2 your right."


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	if is_disabled:
		return
	_swings += 1
	_extra(weapon, "on_attack", [user, ctx])


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	_extra(weapon, "on_hit_target", [user, target])


func _extra(weapon: Weapon, hook: String, args: Array) -> void:
	var sibling: Modifier = null
	if _swings % 2 == 1:
		sibling = weapon.get_left_modifier(slot_index)
	else:
		sibling = weapon.get_right_modifier(slot_index)
	if sibling == null or sibling == self or sibling.is_retrigger_modifier:
		return
	if sibling.is_disabled:
		return
	match hook:
		"on_attack":
			sibling.on_attack(weapon, args[0], args[1])
		"on_hit_target":
			sibling.on_hit_target(weapon, args[0], args[1])
