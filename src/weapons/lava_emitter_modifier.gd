class_name LavaEmitterModifier
extends Modifier

const LAVA_RADIUS: float = 6.0


func _init() -> void:
	name = "Lava Emitter"
	description = "Spawns lava around the user when the weapon is used."
	icon_texture = preload("res://textures/Modifiers/lava_emitter.png")


func on_use(_weapon: Weapon, user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = _weapon._sprite.global_position if _weapon._sprite else user.global_position
	world_manager.place_lava(pos, LAVA_RADIUS)


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null