class_name LavaEmitterModifier
extends Modifier

const LAVA_RADIUS: float = 6.0
const SPLASH_RADIUS: float = 4.0
const FORWARD_OFFSET: float = 14.0
const SIDE_OFFSET: float = 10.0


func _init() -> void:
	name = "Lava Emitter"
	description = "Spawns lava in front of the weapon when used."
	icon_texture = preload("res://textures/Modifiers/lava_emitter.png")


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel: Variant = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN


func on_use(_weapon: Weapon, user: Node) -> void:
	var origin: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
	var dir: Vector2 = _get_facing_direction(user)
	var perp: Vector2 = dir.orthogonal()
	TerrainSurface.place_lava(origin + dir * FORWARD_OFFSET, LAVA_RADIUS)
	TerrainSurface.place_lava(origin + dir * FORWARD_OFFSET + perp * SIDE_OFFSET, SPLASH_RADIUS)
	TerrainSurface.place_lava(origin + dir * FORWARD_OFFSET - perp * SIDE_OFFSET, SPLASH_RADIUS)