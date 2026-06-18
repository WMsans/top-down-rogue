class_name IcicleVolleyModifier
extends ProjectileModifier

func _init() -> void:
	name = "Icicle Volley"
	description = "Every strike fires five icicles."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, 5, 30.0,
		{ "hit_status": "chilly", "tint": Color(0.5, 0.8, 1.0) })
