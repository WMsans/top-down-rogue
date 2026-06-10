class_name BouncingBulletsModifier
extends ProjectileModifier

func _init() -> void:
	name = "Bouncing Bullets"
	description = "Forward spin summons a skyward shockwave that looses four bouncing bullets."
	icon_texture = preload("res://textures/wall.png")
	period = 3
	fire_on = [2]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 3.0, 4, 40.0,
		{ "tint": Color(0.7, 0.95, 1.0), "make_behaviors": func() -> Array: return [BounceBehavior.new()] })
