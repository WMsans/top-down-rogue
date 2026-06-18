class_name ClusterBombModifier
extends ProjectileModifier

const BOMB_DAMAGE := 5.0
const FRAGMENTS := 8

func _init() -> void:
	name = "Cluster Bomb"
	description = "Hurls a bomb that bursts into a ring of fragments."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	var sb := SplitBehavior.new()
	sb.shard_count = FRAGMENTS
	sb.spread_deg = 360.0
	sb.shard_hit_status = "burn"
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], BOMB_DAMAGE,
		{ "behaviors": [sb], "tint": Color(1.0, 0.6, 0.3) })
