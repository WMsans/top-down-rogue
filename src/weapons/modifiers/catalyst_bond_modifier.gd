class_name CatalystBondModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Catalyst Bond"
	description = "Link slots 1 and 3: either fires and both fire."


func get_state_tag() -> String:
	if is_disabled:
		return "disabled"
	return "linked"


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var s0: Modifier = weapon.get_modifier_at(0)
	var s2: Modifier = weapon.get_modifier_at(2)
	if s0 != null and s0 != self and not s0.is_disabled:
		s0.on_hit_target(weapon, user, target)
	if s2 != null and s2 != self and not s2.is_disabled:
		s2.on_hit_target(weapon, user, target)
