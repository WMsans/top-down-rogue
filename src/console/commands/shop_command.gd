extends RefCounted

const SHOP_STALL_SCENE := preload("res://scenes/economy/shop_stall.tscn")


static func register(registry: CommandRegistry) -> void:
	registry.register("shop", "Spawn a shop stall next to the player", _shop)


static func _shop(_args: Array[String], ctx: Dictionary) -> String:
	var player: Node = ctx.get("player")
	if player == null:
		return "error: no player found"
	var parent: Node = player.get_parent()
	if parent == null:
		return "error: player has no parent"
	var stall := SHOP_STALL_SCENE.instantiate()
	parent.add_child(stall)
	stall.global_position = player.global_position + Vector2(0, -60)
	return "Spawned shop stall"
