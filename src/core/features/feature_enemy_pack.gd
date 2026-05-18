class_name FeatureEnemyPack
extends ArenaFeature

@export var enemy_scene: PackedScene
@export var count: int = 4
@export var is_elite: bool = false

func apply(ctx) -> void:
	for i in count:
		var pos: Variant = _sample_air(ctx)
		if pos == null:
			continue
		ctx.dispatcher.spawn_enemy(pos, enemy_scene, is_elite)

func _sample_air(ctx) -> Variant:
	if region == null:
		return null
	for retry in 8:
		var local: Vector2 = region.sample(ctx.rng)
		var world: Vector2 = ctx.anchor_world_pos + local
		if ctx.mask_air.call(world):
			return world
	return null
