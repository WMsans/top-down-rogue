extends Node

signal lights_toggled(enabled: bool)

var lights_enabled: bool = true


func set_lights(enabled: bool) -> void:
	if lights_enabled == enabled:
		return
	lights_enabled = enabled
	lights_toggled.emit(enabled)


func are_lights_enabled() -> bool:
	return lights_enabled
