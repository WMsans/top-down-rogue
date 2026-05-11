class_name JuicyPanel
extends Control

signal opened
signal closed

@export var has_backdrop: bool = true
@export var backdrop_color: Color = Color(0, 0, 0, 0.55)
@export var close_on_backdrop_click: bool = true
@export var content_root: NodePath = NodePath("")
@export var animated_root: NodePath = NodePath("")
@export var drop_distance: float = 80.0
@export var enter_duration: float = 0.45
@export var exit_duration: float = 0.35
@export var stagger_delay: float = 0.05

var _is_open: bool = false
var _is_animating: bool = false
var _rest_position: Vector2 = Vector2.ZERO
var _animated_node: Control = null
var _content_node: Node = null
var _content_rest_positions: Dictionary = {}
var _backdrop: ColorRect = null
var _open_tween: Tween = null
var _close_tween: Tween = null
var _original_mouse_filter: int = MOUSE_FILTER_STOP

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_mouse_filter = mouse_filter
	_resolve_nodes()
	_update_pivot()
	resized.connect(_update_pivot)
	if _animated_node:
		_rest_position = _animated_node.position
	visible = false
	_is_open = false

func _resolve_nodes() -> void:
	if animated_root.is_empty():
		_animated_node = self
	else:
		_animated_node = get_node_or_null(animated_root) as Control
		if _animated_node == null:
			push_warning("JuicyPanel: animated_root resolved to null; falling back to self.")
			_animated_node = self
	if not content_root.is_empty():
		_content_node = get_node_or_null(content_root)

func _update_pivot() -> void:
	if _animated_node:
		_animated_node.pivot_offset = _animated_node.size * 0.5

func open() -> void:
	pass # implemented in Task 2

func close() -> void:
	pass # implemented in Task 3
