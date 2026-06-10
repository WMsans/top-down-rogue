class_name PenetratingShockwaveModifier
extends Modifier

func _init() -> void:
	name = "Penetrating Shockwave"
	description = "Full charge fires a massive penetrating shockwave that deletes enemy projectiles as it travels."
	icon_texture = preload("res://textures/wall.png")

func on_attack(_weapon, user, ctx) -> void:
	if not ctx.get("charged", false):
		return
	if ctx.get("charge_ratio", 0.0) < 1.0:
		return
	ModifierProjectile.spawn_one(user, ctx["origin"], ctx["direction"], 8.0, {
		"behaviors": [PenetrateBehavior.new(), ClearBulletsBehavior.new()],
		"speed": 180.0,
		"lifetime": 2.5,
		"tint": Color(0.6, 0.4, 1.0),
	})
