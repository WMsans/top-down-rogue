extends RefCounted

const OVERLAY_NAME := "AiDebugOverlay"


static func register(registry: CommandRegistry) -> void:
	registry.register("ai_debug", "Toggle enemy AI overlay (tokens, ring slots, firing spots, aim)", _ai_debug)


static func _ai_debug(_args: Array[String], ctx: Dictionary) -> String:
	var wm: Node = ctx.get("world_manager")
	if wm == null:
		return "error: No world loaded."
	var existing := wm.get_node_or_null(OVERLAY_NAME)
	if existing != null:
		wm.remove_child(existing)
		existing.queue_free()
		return "AI debug overlay off"
	var overlay := AiDebugOverlay.new()
	overlay.name = OVERLAY_NAME
	overlay.director = wm.get("encounter_director")
	wm.add_child(overlay)
	return "AI debug overlay on"
