class_name ProjectileModifier
extends Modifier

var period: int = 1
var fire_on: Array = [0]
var _hits: int = 0


func on_attack(weapon: Weapon, user: Node, ctx: Dictionary) -> void:
	var pos: int = _hits % period
	_hits += 1
	if pos in fire_on:
		_fire(weapon, user, ctx)


func _fire(_weapon: Weapon, _user: Node, _ctx: Dictionary) -> void:
	pass
