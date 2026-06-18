class_name PiercingLanceModifier
extends ProjectileModifier

const LANCE_DAMAGE := 4.0
const LANCE_LIFETIME := 2.0

func _init() -> void:
	name = "Piercing Lance"
	description = "Looses a lance that skewers every foe in a line."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], LANCE_DAMAGE,
		{ "behaviors": [PenetrateBehavior.new()], "lifetime": LANCE_LIFETIME, "tint": Color(1.0, 0.9, 0.5) })
