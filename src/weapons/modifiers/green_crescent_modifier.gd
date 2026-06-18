class_name GreenCrescentModifier
extends ProjectileModifier

func _init() -> void:
	name = "Green Crescent"
	description = "Spin slash hurls a crescent of green energy that cuts through enemies in its path."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 5.0,
		{ "behaviors": [PenetrateBehavior.new()], "tint": Color(0.4, 1.0, 0.4) })
