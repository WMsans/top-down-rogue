class_name LavaEmitterModifier
extends Modifier

const LAVA_RADIUS: float = 6.0


func _init() -> void:
	name = "Lava Emitter"
	description = "Spawns lava around the user when the weapon is used."
	icon_texture = preload("res://textures/Modifiers/lava_emitter.png")


func on_use(_weapon: Weapon, user: Node) -> void:
	var pos: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
	TerrainSurface.place_lava(pos, LAVA_RADIUS)