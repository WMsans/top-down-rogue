class_name FeatureHazardFlood
extends ArenaFeature

## Floods the room with a hazard material (resolved from MaterialRegistry at runtime,
## since material ids are assigned dynamically). Used by the Reactor Chamber.

@export_enum("Lava:0", "Oil:1", "Water:2") var hazard: int = 0
@export var radius: float = 40.0
@export var edge_jitter: float = 0.4


func apply(ctx) -> void:
	var mat: int = MaterialRegistry.MAT_LAVA
	if hazard == 1:
		mat = MaterialRegistry.MAT_OIL
	elif hazard == 2:
		mat = MaterialRegistry.MAT_WATER
	ctx.dispatcher.stamp_material_blob(ctx.anchor_world_pos, radius, mat, ctx.rng.randi(), edge_jitter)
