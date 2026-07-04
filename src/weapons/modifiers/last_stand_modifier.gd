class_name LastStandModifier
extends Modifier

const BOOST_MULT := 1.6
var _charged: bool = false
var _prev_hp: float = -1.0


func _init() -> void:
	category = "trigger"
	name = "Last Stand"
	description = "+60% damage on your first hit after taking damage."


func modify_hit_damage(_weapon: Weapon, user: Node, _target: Node, dmg: float) -> float:
	if is_disabled:
		return dmg
	var hp: float = _user_hp(user)
	if _prev_hp >= 0.0 and hp < _prev_hp:
		_charged = true
	_prev_hp = hp
	if _charged:
		_charged = false
		return dmg * BOOST_MULT
	return dmg


func _user_hp(user: Node) -> float:
	if user == null or not ("health" in user):
		return 1.0
	return float(user.health)
