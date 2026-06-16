class_name RicochetShardModifier
extends ProjectileModifier

const SHARD_DAMAGE := 3.0
const BOUNCES := 3

func _init() -> void:
	name = "Ricochet Shard"
	description = "Swings fling a shard that ricochets off walls, striking again."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	var b := BounceBehavior.new()
	b.max_bounces = BOUNCES
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], SHARD_DAMAGE,
		{ "behaviors": [b], "tint": Color(0.8, 0.9, 1.0) })
