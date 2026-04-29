extends RefCounted

static func register(registry: CommandRegistry) -> void:
	registry.register("gamemode", "Switch gamemode (0=survival, 1=creative)", _gamemode)


static func _gamemode(args: Array[String], _ctx: Dictionary) -> String:
	if args.is_empty():
		var current := GameModeManager.get_mode()
		return "Current gamemode: %d (%s)" % [current, GameModeManager.Mode.keys()[current]]
	if not args[0].is_valid_int():
		return "error: Invalid gamemode '%s'. Use 0 (survival) or 1 (creative)." % args[0]
	var mode_int := args[0].to_int()
	if mode_int < 0 or mode_int > 1:
		return "error: Unknown gamemode %d. Use 0 (survival) or 1 (creative)." % mode_int
	var mode: GameModeManager.Mode = mode_int as GameModeManager.Mode
	GameModeManager.set_mode(mode)
	return "Set gamemode to %s" % GameModeManager.Mode.keys()[mode]
