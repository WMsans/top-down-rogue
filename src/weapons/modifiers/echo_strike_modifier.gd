class_name EchoStrikeModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	is_retrigger_modifier = true
	name = "Echo Strike"
	description = "Retrigger your first modifier once per swing."


func on_hit_target(weapon: Weapon, user: Node, target: Node) -> void:
	if is_disabled:
		return
	var first: Modifier = weapon.get_first_modifier()
	if first == null or first == self:
		return
	weapon.retrigger_modifier(first, "on_hit_target", [user, target])


func modify_hit_damage(weapon: Weapon, user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var first: Modifier = weapon.get_first_modifier()
	if first == null or first == self:
		return dmg
	var r: Variant = weapon.retrigger_modifier(first, "modify_hit_damage", [user, target, dmg])
	if r == null:
		return dmg
	return float(r)
