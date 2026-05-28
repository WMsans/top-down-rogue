class_name FeatureWoodWall
extends ArenaFeature

@export var inner_radius: float = 120.0
@export var outer_radius: float = 128.0

func apply(ctx) -> void:
	ctx.dispatcher.stamp_material_ring(
		ctx.anchor_world_pos,
		inner_radius,
		outer_radius,
		MaterialRegistry.MAT_WOOD,
	)
