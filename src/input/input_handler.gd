extends Node

const FIRE_RADIUS := 5.0
const GAS_RADIUS := 6.0
const GAS_DENSITY := 200

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var viewport := get_viewport()
		var camera := viewport.get_camera_2d()
		if camera == null:
			return
		var screen_pos := viewport.get_mouse_position()
		var view_size := viewport.get_visible_rect().size
		var world_pos := (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
		if event.button_index == MOUSE_BUTTON_LEFT:
			world_manager.place_gas(world_pos, GAS_RADIUS, GAS_DENSITY)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			world_manager.place_lava(world_pos, 5.0)
