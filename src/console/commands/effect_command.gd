extends RefCounted


static func register(registry: CommandRegistry) -> void:
	for id in StatusRegistry._defs:
		registry.register("effect " + id, "Apply " + id + " to the player (default 5 seconds)", _apply_effect.bind(id))


static func _apply_effect(args: Array[String], ctx: Dictionary, id: String) -> String:
	var duration := 5.0
	if args.size() > 0 and args[0].is_valid_float():
		duration = args[0].to_float()
	if duration <= 0.0:
		return "error: duration must be positive"

	var player: Node = ctx.get("player")
	if player == null:
		return "error: no player found"

	var sc: StatusComponent = player.get_node_or_null("StatusComponent")
	if sc == null:
		return "error: player has no StatusComponent"

	var def: StatusDef = StatusRegistry.get_def(id)
	if def == null:
		return "error: unknown status '" + id + "'"

	var stain: float = def.active_threshold + def.decay_rate * duration
	sc.add_stain(id, stain)
	return "Applied " + id + " for " + str(duration) + "s"
