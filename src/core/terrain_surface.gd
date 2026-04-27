extends Node

var adapter = null


func register_adapter(a) -> void:
	adapter = a


func place_gas(world_pos: Vector2, radius: float, density: int, velocity: Vector2i = Vector2i.ZERO) -> void:
	if adapter:
		adapter.place_gas(world_pos, radius, density, velocity)


func place_lava(world_pos: Vector2, radius: float) -> void:
	if adapter:
		adapter.place_lava(world_pos, radius)


func place_fire(world_pos: Vector2, radius: float) -> void:
	if adapter:
		adapter.place_fire(world_pos, radius)


func clear_and_push_materials_in_arc(origin: Vector2, direction: Vector2, radius: float, arc_angle: float, push_speed: float, edge_fraction: float, materials: Array) -> void:
	if adapter:
		adapter.clear_and_push_materials_in_arc(origin, direction, radius, arc_angle, push_speed, edge_fraction, materials)


func read_region(rect: Rect2i) -> PackedByteArray:
	if adapter:
		return adapter.read_region(rect)
	return PackedByteArray()


func find_spawn_position(origin: Vector2i, body_size: Vector2i, max_radius: float = 800.0) -> Vector2i:
	if adapter:
		return adapter.find_spawn_position(origin, body_size, max_radius)
	return Vector2i.ZERO


func get_active_chunk_coords() -> Array:
	if adapter:
		return adapter.get_active_chunk_coords()
	return []
