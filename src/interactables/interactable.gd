class_name Interactable
extends Node

signal highlighted
signal unhighlighted

@export var interaction_name: String = ""
@export var outline_material: ShaderMaterial

var _is_highlighted: bool = false


func set_highlighted(enabled: bool) -> void:
	if _is_highlighted == enabled:
		return
	_is_highlighted = enabled
	if outline_material:
		outline_material.set_shader_parameter("outline_width", 2.0 if enabled else 0.0)
	if enabled:
		highlighted.emit()
	else:
		unhighlighted.emit()


func interact(player: Node) -> void:
	var parent := get_parent()
	if parent and parent.has_method("interact"):
		parent.interact(player)