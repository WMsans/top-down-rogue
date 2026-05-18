class_name FeatureVent
extends ArenaFeature

@export var vent_scene: PackedScene
@export var count: int = 1

func apply(ctx) -> void:
	if vent_scene == null:
		return
	for i in count:
		var pos: Variant = _sample_air(ctx)
		if pos == null:
			continue
		ctx.dispatcher.spawn_prop(pos, vent_scene)

func _sample_air(ctx) -> Variant:
	if region == null:
		return null
	for retry in 8:
		var local: Vector2 = region.sample(ctx.rng)
		var world: Vector2 = ctx.anchor_world_pos + local
		if ctx.mask_air.call(world):
			return world
	return null
