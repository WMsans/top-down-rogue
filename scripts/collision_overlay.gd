extends Node2D

const LINE_COLOR := Color(1.0, 0.0, 1.0, 0.8)
const LINE_WIDTH := 2.0

@onready var world_manager: Node2D = get_parent().get_parent().get_node("WorldManager")

func _process(_delta: float) -> void:
	if is_visible_in_tree() and Engine.is_editor_hint() == false:
		queue_redraw()

func _draw() -> void:
	if world_manager == null:
		return

	var chunks: Dictionary = world_manager.chunks
	for coord in chunks:
		var chunk: Chunk = chunks[coord]
		if chunk.static_body == null or not is_instance_valid(chunk.static_body):
			continue
		var collision_shape: CollisionShape2D = chunk.static_body.get_child(0) if chunk.static_body.get_child_count() > 0 else null
		if collision_shape == null or collision_shape.shape == null:
			continue

		var shape: ConcavePolygonShape2D = collision_shape.shape
		var segments: PackedVector2Array = shape.segments

		for i in range(0, segments.size(), 2):
			var start: Vector2 = segments[i]
			var end: Vector2 = segments[i + 1]
			var start_world: Vector2 = chunk.static_body.to_global(start)
			var end_world: Vector2 = chunk.static_body.to_global(end)
			var start_local: Vector2 = to_local(start_world)
			var end_local: Vector2 = to_local(end_world)
			draw_line(start_local, end_local, LINE_COLOR, LINE_WIDTH)