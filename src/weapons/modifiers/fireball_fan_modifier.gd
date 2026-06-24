class_name FireballFanModifier
extends ProjectileModifier

const FAN_COUNT := 3

func _init() -> void:
	name = "Fireball Fan"
	description = "Every swing looses a fan of three fireballs."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, FAN_COUNT, 30.0,
		{ "hit_status": "on_fire", "tint": Color(1.0, 0.5, 0.1) })
