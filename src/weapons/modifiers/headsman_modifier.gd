class_name HeadsmanModifier
extends Modifier

# Refunds half of the remaining cooldown wait on a kill.
const REFUND_FRACTION := 0.5


func _init() -> void:
	category = "trigger"
	name = "Headsman"
	description = "Kills refund 50% of the swing cooldown."


func on_kill(weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	weapon.refund_cooldown(REFUND_FRACTION)
