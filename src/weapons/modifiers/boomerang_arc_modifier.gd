class_name BoomerangArcModifier
extends ProjectileModifier

const ARC_DAMAGE := 3.0

func _init() -> void:
	name = "Boomerang Arc"
	description = "Throws a blade-arc that returns, hitting foes both ways."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], ARC_DAMAGE,
		{ "behaviors": [ReturnBehavior.new()], "tint": Color(0.9, 0.85, 0.6) })
