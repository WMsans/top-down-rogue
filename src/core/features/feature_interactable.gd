class_name FeatureInteractable
extends ArenaFeature

## Places an InteractableShrine subclass (by script) at the room anchor.

@export var shrine_script: Script = null
@export var offset: Vector2 = Vector2.ZERO


func apply(ctx) -> void:
	if shrine_script == null:
		return
	var shrine = shrine_script.new()
	ctx.dispatcher.spawn_node(shrine, ctx.anchor_world_pos + offset)
