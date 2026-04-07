extends Node

const GAS_RADIUS := 5.0

@onready var world_manager: Node2D = get_parent().get_node("WorldManager")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos := world_manager.get_global_mouse_position()
			world_manager.place_gas(world_pos, GAS_RADIUS)
