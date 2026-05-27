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
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	spr.region_enabled = true
	spr.region_rect = Rect2(Vector2.ZERO, size)
	ctx.dispatcher.spawn_node(spr, ctx.anchor_world_pos + offset)
