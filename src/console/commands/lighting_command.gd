extends RefCounted

static func register(registry: CommandRegistry) -> void:
	registry.register("lighting", "Toggle dynamic lava lighting (on/off)", _lighting)


static func _lighting(args: Array[String], _ctx: Dictionary) -> String:
	if args.is_empty():
		return "Lighting is %s" % ("on" if LightingManager.enabled else "off")
	var arg := args[0].to_lower()
	if arg == "on":
		LightingManager.enabled = true
		return "Lighting on"
	if arg == "off":
		LightingManager.enabled = false
		return "Lighting off"
	return "error: expected 'on' or 'off'"
