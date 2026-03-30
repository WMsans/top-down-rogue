extends Node2D

const LINE_COLOR := Color(1.0, 0.0, 1.0, 0.8)
const LINE_WIDTH := 2.0

@onready var player: Node2D = get_parent().get_parent().get_node("Player")

func _process(_delta: float) -> void:
	if is_visible_in_tree() and Engine.is_editor_hint() == false:
		queue_redraw()

func _draw() -> void:
	if player == null:
		return
	
	var terrain_collider: StaticBody2D = player.get("_terrain_collider")
	if terrain_collider == null or not terrain_collider.is_inside_tree():
		return
	
	var collision_shape: CollisionShape2D = terrain_collider.get("_collision_shape")
	if collision_shape == null or collision_shape.shape == null:
		return
	
	var shape: ConcavePolygonShape2D = collision_shape.shape
	var segments: PackedVector2Array = shape.segments
	
# Draw each segment as a line
	for i in range(0, segments.size(), 2):
		var start: Vector2 = segments[i]
		var end: Vector2 = segments[i + 1]
# Convert from TerrainCollider local space to world space
		var start_world: Vector2 = terrain_collider.to_global(start)
		var end_world: Vector2 = terrain_collider.to_global(end)
# Convert to local space for drawing
		var start_local: Vector2 = to_local(start_world)
		var end_local: Vector2 = to_local(end_world)
		draw_line(start_local, end_local, LINE_COLOR, LINE_WIDTH)