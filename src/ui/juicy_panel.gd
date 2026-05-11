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
	_setup_backdrop()
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

func _setup_backdrop() -> void:
	if not has_backdrop:
		return
	var existing := get_node_or_null("_Backdrop") as ColorRect
	if existing:
		_backdrop = existing
	else:
		_backdrop = ColorRect.new()
		_backdrop.name = "_Backdrop"
		_backdrop.color = Color(backdrop_color.r, backdrop_color.g, backdrop_color.b, 0.0)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_backdrop)
		move_child(_backdrop, 0)
	if close_on_backdrop_click:
		if not _backdrop.gui_input.is_connected(_on_backdrop_input):
			_backdrop.gui_input.connect(_on_backdrop_input)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

func _update_pivot() -> void:
	if _animated_node:
		_animated_node.pivot_offset = _animated_node.size * 0.5

func _prepare_open_state() -> void:
	_rest_position = _animated_node.position
	_animated_node.position = _rest_position - Vector2(0, drop_distance)
	_animated_node.modulate.a = 0.0
	_animated_node.scale = Vector2(0.96, 1.04)
	if _backdrop:
		_backdrop.color.a = 0.0
	_update_pivot()

func _on_open_finished() -> void:
	_is_animating = false
	mouse_filter = _original_mouse_filter
	opened.emit()

func _on_close_finished() -> void:
	_is_animating = false
	visible = false
	mouse_filter = _original_mouse_filter
	if _animated_node:
		_animated_node.position = _rest_position
		_animated_node.scale = Vector2.ONE
		_animated_node.modulate.a = 1.0
	closed.emit()

func open() -> void:
	if _is_open and not _is_animating:
		return
	if _is_animating and _open_tween and _open_tween.is_running():
		return
	if _close_tween and _close_tween.is_running():
		_close_tween.kill()
		_close_tween = null
	_is_open = true
	_is_animating = true
	visible = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_prepare_open_state()
	_open_tween = create_tween()
	_open_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_open_tween.set_parallel(true)
	if _backdrop:
		_open_tween.tween_property(_backdrop, "color:a", backdrop_color.a, 0.18).set_trans(Tween.TRANS_LINEAR)
	var target_pos := _rest_position
	_open_tween.tween_property(_animated_node, "position:y", target_pos.y, enter_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_animated_node, "modulate:a", 1.0, enter_duration * 0.4).set_trans(Tween.TRANS_LINEAR)
	_open_tween.tween_property(_animated_node, "scale", Vector2.ONE, enter_duration * 0.9).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_open_tween.finished.connect(_on_open_finished, CONNECT_ONE_SHOT)

func close() -> void:
	if not _is_open and not _is_animating:
		return
	if _is_animating and _close_tween and _close_tween.is_running():
		return
	if _open_tween and _open_tween.is_running():
		_open_tween.kill()
		_open_tween = null
	_is_open = false
	_is_animating = true
	mouse_filter = MOUSE_FILTER_IGNORE
	_close_tween = create_tween()
	_close_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_close_tween.tween_interval(0.05)
	_close_tween.set_parallel(true)
	if _backdrop:
		_close_tween.tween_property(_backdrop, "color:a", 0.0, 0.18).set_trans(Tween.TRANS_LINEAR)
	var fall_y := _rest_position.y + drop_distance
	_close_tween.tween_property(_animated_node, "position:y", fall_y, exit_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_close_tween.tween_property(_animated_node, "scale", Vector2(1.02, 0.94), exit_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_close_tween.chain().tween_interval(exit_duration * 0.4)
	_close_tween.tween_property(_animated_node, "modulate:a", 0.0, exit_duration * 0.6).set_trans(Tween.TRANS_LINEAR)
	_close_tween.finished.connect(_on_close_finished, CONNECT_ONE_SHOT)
