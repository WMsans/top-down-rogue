class_name FeaturePoolPatch
extends ArenaFeature

@export var material_id: int = 0
@export var count: int = 1
@export var size_min_cells: int = 6
@export var size_max_cells: int = 14

func apply(ctx) -> void:
	if material_id <= 0:
		return
	for i in count:
		var pos: Variant = _sample_air(ctx)
		if pos == null:
			continue
		var radius: int = ctx.rng.randi_range(size_min_cells, size_max_cells)
		ctx.dispatcher.stamp_material_disc(pos, radius, material_id)

func _sample_air(ctx) -> Variant:
	if region == null:
		return null
	for retry in 16:
		var local: Vector2 = region.sample(ctx.rng)
		var world: Vector2 = ctx.anchor_world_pos + local
		if ctx.mask_air.call(world):
			return world
	return null
