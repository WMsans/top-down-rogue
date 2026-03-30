extends Node2D

const LINE_COLOR := Color(1.0, 0.2, 0.2, 0.6)
const LINE_WIDTH := 0.5

var _terrain_collider: StaticBody2D


func _ready() -> void:
	# Find the TerrainCollider via the player (our parent is DebugManager, grandparent is Main)
	var world_manager: Node2D = get_parent().get_parent().get_node("WorldManager")
	await world_manager.get_tree().process_frame
	_terrain_collider = world_manager.player.get_node("TerrainCollider") if world_manager.player else null


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		if _terrain_collider == null:
			var world_manager: Node2D = get_parent().get_parent().get_node("WorldManager")
			if world_manager.player:
				_terrain_collider = world_manager.player.get_node("TerrainCollider")
		queue_redraw()


func _draw() -> void:
	if _terrain_collider == null:
		return

	for child in _terrain_collider.get_children():
		if child is CollisionPolygon2D:
			var poly: PackedVector2Array = child.polygon
			if poly.size() < 3:
				continue
			# Polygons are in world space (TerrainCollider has top_level = true)
			# We need to convert to our local space for drawing
			var local_poly := PackedVector2Array()
			for point in poly:
				local_poly.append(to_local(point))
			# Draw outline
			for i in range(local_poly.size()):
				var from := local_poly[i]
				var to := local_poly[(i + 1) % local_poly.size()]
				draw_line(from, to, LINE_COLOR, LINE_WIDTH)
