class_name Interactable
extends Node

signal highlighted
signal unhighlighted

@export var interaction_name: String = ""
@export var canvas_item: CanvasItem

var _is_highlighted: bool = false


func _ready() -> void:
	if canvas_item and canvas_item.material is ShaderMaterial:
		canvas_item.material = (canvas_item.material as ShaderMaterial).duplicate()


func set_highlighted(enabled: bool) -> void:
	if _is_highlighted == enabled:
		return
	_is_highlighted = enabled
	if canvas_item and canvas_item.material is ShaderMaterial:
		(canvas_item.material as ShaderMaterial).set_shader_parameter("outline_width", 1.0 if enabled else 0.0)
	if enabled:
		highlighted.emit()
	else:
		unhighlighted.emit()


func interact(player: Node) -> void:
	var parent := get_parent()
	if parent and parent.has_method("interact"):
		parent.interact(player)
