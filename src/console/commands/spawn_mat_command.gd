extends RefCounted

const DEFAULT_RADIUS: float = 5.0
const GAS_DENSITY: int = 200


static func register(registry: CommandRegistry) -> void:
	for mat in MaterialRegistry.materials:
		if mat.id == MaterialRegistry.MAT_AIR:
			continue
		var type := mat.name.to_lower()
		registry.register("spawn_mat " + type, "Place " + type + " at mouse", _spawn_mat.bind(type))


static func _spawn_mat(type: String, args: Array[String], ctx: Dictionary) -> String:
	var world_manager: Node = ctx.get("world_manager")
	if world_manager == null:
		return "error: no world manager in scene"

	var radius: float = DEFAULT_RADIUS
	if args.size() > 0 and args[0].is_valid_float():
		radius = args[0].to_float()

	var density := GAS_DENSITY
	if args.size() > 1 and args[1].is_valid_int():
		density = args[1].to_int()

	var world_pos: Vector2 = ctx.get("world_pos", Vector2.ZERO)

	var mat_id: int = -1
	for mat in MaterialRegistry.materials:
		if mat.name.to_lower() == type:
			mat_id = mat.id
			break

	if mat_id == -1:
		return "error: unknown material '" + type + "'"

	if mat_id == MaterialRegistry.MAT_GAS:
		world_manager.place_gas(world_pos, radius, density)
	else:
		world_manager.place_material(world_pos, radius, mat_id)

	return "Placed " + type + " at mouse"
