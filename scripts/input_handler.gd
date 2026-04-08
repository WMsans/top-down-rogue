extends Node

const FIRE_RADIUS := 5.0
const GAS_RADIUS := 6.0
const GAS_DENSITY := 200

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var world_pos := world_manager.get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			world_manager.place_fire(world_pos, FIRE_RADIUS)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			world_manager.place_gas(world_pos, GAS_RADIUS, GAS_DENSITY)