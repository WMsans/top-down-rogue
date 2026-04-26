extends RefCounted

const DEFAULT_RADIUS: float = 5.0
const GAS_DENSITY: int = 200


static func register(registry: CommandRegistry) -> void:
	for mat in MaterialRegistry.materials:
		if mat.fluid:
			var type := mat.name.to_lower()
			registry.register("spawn_mat " + type, "Place " + type + " at mouse", _spawn_mat.bind(type))


static func _spawn_mat(type: String, args: Array[String], ctx: Dictionary) -> String:
	var world_manager := ctx.get("world_manager")
	if world_manager == null:
		return "error: no world manager in scene"

	var radius: float = DEFAULT_RADIUS
	if args.size() > 0 and args[0].is_valid_float():
		radius = args[0].to_float()

	var density := GAS_DENSITY
	if args.size() > 1 and args[1].is_valid_int():
		density = args[1].to_int()

	var world_pos: Vector2 = ctx.get("world_pos", Vector2.ZERO)

	if type == "gas":
		world_manager.place_gas(world_pos, radius, density)
	else:
		world_manager.call("place_" + type, world_pos, radius)

	return "Placed " + type + " at mouse"
