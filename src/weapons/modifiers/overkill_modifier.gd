class_name OverkillModifier
extends Modifier

var _carry: float = 0.0
var _last_dmg: float = 0.0
var _last_pre_hp: float = 0.0


func _init() -> void:
	category = "trigger"
	name = "Overkill"
	description = "Damage exceeding an enemy's HP carries to the next enemy hit."


func modify_hit_damage(_weapon: Weapon, _user: Node, target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	_last_pre_hp = float(target.health) if (target != null and "health" in target) else 0.0
	var out: float = dmg + _carry
	_last_dmg = out
	_carry = 0.0
	return out


func on_kill(_weapon: Weapon, _user: Node, _target: Node) -> void:
	if is_disabled:
		return
	_carry = maxf(0.0, _last_dmg - _last_pre_hp)
