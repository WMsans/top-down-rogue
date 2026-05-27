extends RefCounted


static func register(registry: CommandRegistry) -> void:
	registry.register("tp", "Teleport player to x y coordinates", _tp)


static func _tp(args: Array[String], ctx: Dictionary) -> String:
	if args.size() < 2:
		return "error: usage: tp <x> <y>"
	if not args[0].is_valid_float() or not args[1].is_valid_float():
		return "error: x and y must be numbers"

	var player: Node2D = ctx.get("player")
	if player == null:
		return "error: no player found"

	var x := args[0].to_float()
	var y := args[1].to_float()
	player.global_position = Vector2(x, y)
	return "Teleported to (%d, %d)" % [x as int, y as int]
