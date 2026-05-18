class_name FeaturePillarCluster
extends ArenaFeature

@export var count: int = 6
@export var pillar_radius_cells: int = 10
@export var spacing_min: float = 64.0

func apply(ctx) -> void:
	var placed: Array[Vector2] = []
	for i in count:
		var pos: Variant = _try_place(ctx, placed)
		if pos == null:
			continue
		placed.append(pos)
		ctx.dispatcher.stamp_material_disc(pos, pillar_radius_cells, ctx.background_material)

func _try_place(ctx, placed: Array[Vector2]) -> Variant:
	if region == null:
		return null
	for retry in 24:
		var local: Vector2 = region.sample(ctx.rng)
		var world: Vector2 = ctx.anchor_world_pos + local
		if not ctx.mask_air.call(world):
			continue
		var too_close := false
		for p in placed:
			if p.distance_to(world) < spacing_min:
				too_close = true
				break
		if too_close:
			continue
		return world
	return null
