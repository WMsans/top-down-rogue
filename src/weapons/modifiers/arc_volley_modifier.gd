class_name ArcVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Arc Volley"
	description = "First two hits of a three-hit combo each fire seven projectiles."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [0, 1]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 1.5, 7, 45.0,
		{ "tint": Color(0.9, 0.9, 1.0) })
