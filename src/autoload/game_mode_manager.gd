extends Node

enum Mode { SURVIVAL = 0, CREATIVE = 1 }

var current_mode: Mode = Mode.SURVIVAL


func is_creative() -> bool:
	return current_mode == Mode.CREATIVE


func set_mode(mode: Mode) -> void:
	current_mode = mode


func get_mode() -> Mode:
	return current_mode
