class_name FeatureBossSpawn
extends ArenaFeature

@export var boss_scene: PackedScene
@export var floor_scaling: bool = true

func apply(ctx) -> void:
	ctx.dispatcher.spawn_boss(ctx.anchor_world_pos, boss_scene)
