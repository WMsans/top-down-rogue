class_name FeaturePlaqueSet
extends ArenaFeature

const PlaqueScript = preload("res://src/props/plaque.gd")

@export var plaques: Array[PlaqueSpec] = []

func apply(ctx) -> void:
	for spec in plaques:
		if spec == null or spec.texture == null:
			continue
		var body := StaticBody2D.new()
		body.set_script(PlaqueScript)
		body.collision_layer = 2
		body.collision_mask = 0
		body.sort_pivot_y = spec.size.y * 0.5 - 8.0

		var spr := Sprite2D.new()
		spr.texture = spec.texture
		spr.centered = true
		var tex_size: Vector2 = spec.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			spr.scale = Vector2(spec.size.x / tex_size.x, spec.size.y / tex_size.y)
		body.add_child(spr)

		var foot_height := 28.0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(spec.size.x, foot_height) 
		shape.shape = rect
		shape.position = Vector2(0, spec.size.y * 0.5 - foot_height * 0.5 - 8.0)
		body.add_child(shape)

		ctx.dispatcher.spawn_node(body, ctx.anchor_world_pos + spec.offset)
