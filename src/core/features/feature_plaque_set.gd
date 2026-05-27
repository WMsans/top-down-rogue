class_name FeaturePlaqueSet
extends ArenaFeature

@export var plaques: Array[PlaqueSpec] = []

func apply(ctx) -> void:
	for spec in plaques:
		if spec == null or spec.texture == null:
			continue
		var spr := Sprite2D.new()
		spr.texture = spec.texture
		spr.centered = true
		spr.z_index = spec.z_index_value
		var tex_size: Vector2 = spec.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			spr.scale = Vector2(spec.size.x / tex_size.x, spec.size.y / tex_size.y)
		ctx.dispatcher.spawn_node(spr, ctx.anchor_world_pos + spec.offset)
