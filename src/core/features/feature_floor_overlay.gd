class_name FeatureFloorOverlay
extends ArenaFeature

@export var texture: Texture2D
@export var radius: float = 120.0
@export var offset: Vector2 = Vector2.ZERO
@export var segments: int = 48
@export var z_index_value: int = -5

func apply(ctx) -> void:
	if texture == null:
		return
	var poly := Polygon2D.new()
	poly.texture = texture
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.z_index = z_index_value
	var count : int = max(segments, 3)
	var points := PackedVector2Array()
	points.resize(count)
	for i in count:
		var a := TAU * float(i) / float(count)
		points[i] = Vector2(cos(a), sin(a)) * radius
	poly.polygon = points
	ctx.dispatcher.spawn_node(poly, ctx.anchor_world_pos + offset)
