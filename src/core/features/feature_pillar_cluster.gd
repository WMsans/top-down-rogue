class_name FeaturePillarCluster
extends ArenaFeature

@export var count: int = 6
@export var pillar_radius_cells: int = 10  # used when radius_min<=0
@export var radius_min: int = 0
@export var radius_max: int = 0
@export var large_bias: float = 0.65  # 0..1, probability the sampled radius lands in the upper half of the range
# Minimum allowed distance between centers, as a fraction of the larger radius.
# 2.0 = no overlap; 1.0 = touching edge-to-center; values below 1.0 produce heavy overlap (merged blobs).
@export var center_distance_factor: float = 0.7
# Strength of per-angle radius noise applied at stamp time. 0 = perfect circle,
# 0.25 = noticeably rough edges, 0.4+ = lumpy organic blobs.
@export var edge_jitter: float = 0.3

func apply(ctx) -> void:
	var placed: Array = []  # entries: {"pos": Vector2, "r": float}
	for i in count:
		var r: float = _sample_radius(ctx)
		var pos: Variant = _try_place(ctx, placed, r)
		if pos == null:
			continue
		placed.append({"pos": pos, "r": r})
		var stamp_seed: int = ctx.rng.randi()
		ctx.dispatcher.stamp_material_blob(pos, r, ctx.background_material, stamp_seed, edge_jitter)

func _sample_radius(ctx) -> float:
	if radius_min <= 0 or radius_max <= 0 or radius_max < radius_min:
		return float(pillar_radius_cells)
	var mid: float = float(radius_min + radius_max) * 0.5
	if ctx.rng.randf() < large_bias:
		return ctx.rng.randf_range(mid, float(radius_max))
	return ctx.rng.randf_range(float(radius_min), mid)

func _try_place(ctx, placed: Array, radius: float) -> Variant:
	if region == null:
		return null
	for retry in 24:
		var local: Vector2 = region.sample(ctx.rng)
		var world: Vector2 = ctx.anchor_world_pos + local
		if not ctx.mask_air.call(world):
			continue
		var too_close := false
		for entry in placed:
			var required: float = max(float(entry["r"]), radius) * center_distance_factor
			if entry["pos"].distance_to(world) < required:
				too_close = true
				break
		if too_close:
			continue
		return world
	return null
