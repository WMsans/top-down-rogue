extends RefCounted

static func register(registry: CommandRegistry) -> void:
	registry.register("gamerule light", "Enable/disable all terrain lights (true/false)", _light)


static func _light(args: Array[String], _ctx: Dictionary) -> String:
	if args.is_empty():
		return "gamerule light: " + ("true" if GameRuleManager.are_lights_enabled() else "false")
	var value := args[0].to_lower()
	if value == "true" or value == "1":
		GameRuleManager.set_lights(true)
		return "Terrain lights enabled"
	elif value == "false" or value == "0":
		GameRuleManager.set_lights(false)
		return "Terrain lights disabled"
	return "error: Invalid value '%s'. Use true/false or 1/0." % args[0]
