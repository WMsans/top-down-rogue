class_name HomingHexModifier
extends ProjectileModifier

const HEX_DAMAGE := 3.0

func _init() -> void:
	name = "Homing Hex"
	description = "Every swing looses a bolt that curves toward the nearest foe."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], HEX_DAMAGE,
		{ "behaviors": [HomingBehavior.new()], "tint": Color(0.7, 0.4, 1.0) })
