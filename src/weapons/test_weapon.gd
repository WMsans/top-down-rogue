class_name TestWeapon
extends Weapon

const COOLDOWN: float = 0.5
const GAS_RADIUS: float = 6.0
const GAS_DENSITY: int = 200

var _cooldown_timer: float = 0.0


func _init() -> void:
	name = "Test Weapon"


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return
	
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	
	var pos: Vector2 = user.global_position
	world_manager.place_gas(pos, GAS_RADIUS, GAS_DENSITY)
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