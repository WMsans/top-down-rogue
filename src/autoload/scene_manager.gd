extends Node

signal scene_changed
signal pause_toggled(is_paused: bool)

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _transition_layer: CanvasLayer
var _color_rect: ColorRect
var _is_transitioning := false


func _ready() -> void:
	_create_transition_layer()


func _create_transition_layer() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.layer = 100
	_transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	_color_rect = ColorRect.new()
	_color_rect.color = Color.BLACK
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.anchors_preset = Control.PRESET_FULL_RECT
	_color_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_transition_layer.add_child(_color_rect)
	add_child(_transition_layer)

	_color_rect.visible = false


func go_to_game() -> void:
	_transition_to(GAME_SCENE)


func go_to_main_menu() -> void:
	_transition_to(MAIN_MENU_SCENE)


func _transition_to(target_scene: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	_color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_callback(_color_rect.show)
	tween.tween_property(_color_rect, "color:a", 1.0, 0.5).from(0.0)
	tween.tween_callback(_change_scene.bind(target_scene))
	tween.tween_property(_color_rect, "color:a", 0.0, 0.5).from(1.0)
	tween.tween_callback(_on_transition_complete)


func _change_scene(target_scene: String) -> void:
	get_tree().change_scene_to_file(target_scene)
	scene_changed.emit()


func _on_transition_complete() -> void:
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.visible = false
	_color_rect.color = Color.BLACK
	_is_transitioning = false


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_toggled.emit(paused)