class_name FeatureFloorOverlay
extends ArenaFeature

@export var texture: Texture2D
@export var size: Vector2 = Vector2(1024, 1024)
@export var offset: Vector2 = Vector2.ZERO
@export var z_index_value: int = -5

func apply(ctx) -> void:
	if texture == null:
		return
	var spr := Sprite2D.new()
	spr.texture = texture
	spr.centered = true
	spr.z_index = z_index_value
	var tex_size: Vector2 = texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		spr.scale = Vector2(size.x / tex_size.x, size.y / tex_size.y)
	ctx.dispatcher.spawn_node(spr, ctx.anchor_world_pos + offset)
