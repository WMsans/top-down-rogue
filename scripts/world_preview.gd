@tool
class_name WorldPreview
extends Node2D

@export var preview_size: int = 3
@export var world_seed: int = 0
@export_tool_button("Generate Preview") var generate_preview_button = generate_preview
@export_tool_button("Clear Preview") var clear_preview_button = clear_preview

var _world_manager: Node2D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_find_world_manager()


func _find_world_manager() -> void:
	var parent = get_parent()
	if parent and parent.has_method("generate_chunks_at"):
		_world_manager = parent


func generate_preview() -> void:
	if not _is_ready():
		return

	_world_manager.clear_all_chunks()

	var coords: Array[Vector2i] = []
	for x in range(-preview_size, preview_size + 1):
		for y in range(-preview_size, preview_size + 1):
			coords.append(Vector2i(x, y))

	_world_manager.generate_chunks_at(coords, world_seed)


func clear_preview() -> void:
	if not _is_ready():
		return

	_world_manager.clear_all_chunks()


func _is_ready() -> bool:
	if _world_manager == null:
		_find_world_manager()
	return _world_manager != null
