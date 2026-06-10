class_name TriangularVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Triangular Volley"
	description = "Third hit of a three-hit combo sprays thirteen bolts in a triangular volley."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [2]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 1.5, 13, 60.0,
		{ "tint": Color(0.8, 0.9, 1.0) })
