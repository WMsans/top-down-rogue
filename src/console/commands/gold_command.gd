extends RefCounted


static func register(registry: CommandRegistry) -> void:
	registry.register("gold", "Give the player gold", _gold)


static func _gold(args: Array[String], ctx: Dictionary) -> String:
	var amount := 100
	if args.size() > 0 and args[0].is_valid_int():
		amount = args[0].to_int()

	if amount <= 0:
		return "error: amount must be positive"

	var player: Node = ctx.get("player")
	if player == null:
		return "error: no player found"

	var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
	if inventory == null:
		return "error: player has no inventory"

	inventory.add_gold(amount)
	return "Gave " + str(amount) + " gold"
