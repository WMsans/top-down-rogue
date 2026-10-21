class_name HeadsmanModifier
extends Modifier


func _init() -> void:
	category = "trigger"
	name = "Headsman"
	description = "One-shotting an enemy above 50% HP refunds the swing."


func on_kill(weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	weapon.reset_cooldown()
