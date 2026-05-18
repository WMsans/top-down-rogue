class_name FeatureChestSpawn
extends ArenaFeature

@export var rare: bool = false

func apply(ctx) -> void:
	ctx.dispatcher.spawn_chest(ctx.anchor_world_pos, rare)
