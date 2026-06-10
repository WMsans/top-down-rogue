class_name GleamingProjectileModifier
extends ProjectileModifier

func _init() -> void:
	name = "Gleaming Projectile"
	description = "Every swing releases a gleaming projectile that shatters incoming enemy bullets clearing a path through gunfire."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 3.0,
		{ "behaviors": [ClearBulletsBehavior.new()], "tint": Color(1.0, 1.0, 0.7) })
