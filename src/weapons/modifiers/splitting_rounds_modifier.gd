class_name SplittingRoundsModifier
extends ProjectileModifier

func _init() -> void:
	name = "Splitting Rounds"
	description = "Follow-up thrust scatters three rounds that split into four shards on impact."
	icon_texture = preload("res://textures/wall.png")
	period = 2
	fire_on = [1]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 3.0, 3, 20.0,
		{ "tint": Color(1.0, 0.85, 0.4), "make_behaviors": func() -> Array: return [SplitBehavior.new()] })
