class_name IcicleVolleyModifier
extends ProjectileModifier

const FAN_COUNT := 3
const PIERCING := true

func _init() -> void:
	name = "Icicle Volley"
	description = "Every strike fires three piercing icicles."
	icon_texture = preload("res://textures/wall.png")
	period = 1
	fire_on = [0]

func _fire(_weapon, user, ctx) -> void:
	ModifierProjectile.spawn_fan(user, ctx["origin"], ctx["direction"], 2.0, FAN_COUNT, 30.0,
		{ "hit_status": "chilly", "tint": Color(0.5, 0.8, 1.0), "make_behaviors": func() -> Array: return [PenetrateBehavior.new()] })
