class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const RANGE: float = 40.0
const ARC_ANGLE: float = PI / 2.0
const COOLDOWN: float = 0.5
const PUSH_SPEED: float = 60.0

var _cooldown_timer: float = 0.0


func _init() -> void:
	name = "Melee Weapon"


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	
	var materials: Array[int] = [
		MaterialRegistry.MAT_GAS,
		MaterialRegistry.MAT_LAVA
	]
	world_manager.disperse_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, materials)
	
	_spawn_effect(user, direction)
	_cooldown_timer = COOLDOWN


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN


func _spawn_effect(user: Node, direction: Vector2) -> void:
	var effect_scene := preload("res://scenes/melee_swing_effect.tscn")
	var effect := effect_scene.instantiate()
	effect.global_position = user.global_position
	effect.setup(direction, WEAPON_TEXTURE)
	user.get_tree().current_scene.add_child(effect)