class_name HeadsmanModifier
extends Modifier

const HIGH_HP_FRACTION := 0.5
var _last_frac: float = 0.0


func _init() -> void:
	category = "trigger"
	name = "Headsman"
	description = "One-shotting an enemy above 50% HP refunds the swing."


func modify_hit_damage(_weapon: Weapon, _user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	if target != null and "health" in target and "max_health" in target:
		_last_frac = float(target.health) / maxf(1.0, float(target.max_health))
	return dmg


func on_kill(weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	if _last_frac > HIGH_HP_FRACTION:
		weapon.reset_cooldown()
