extends Node2D

const CHUNK_SIZE := 256
const LINE_COLOR := Color(0.0, 1.0, 0.0, 0.4)
const LINE_WIDTH := 1.0

@onready var world_manager: Node2D = get_parent().get_parent().get_node("WorldManager")

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var coords: Array[Vector2i] = world_manager.get_active_chunk_coords()
	for coord in coords:
		var rect := Rect2(
			Vector2(coord) * CHUNK_SIZE,
			Vector2(CHUNK_SIZE, CHUNK_SIZE)
		)
		draw_rect(rect, LINE_COLOR, false, LINE_WIDTH)
