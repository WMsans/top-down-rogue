extends Node2D

var _debug_label: Label

func _ready() -> void:
	visible = false
	_build_hud()

func _process(_delta: float) -> void:
	if not visible:
		return
	var player := get_node("../Player") as Node2D
	var pos := player.global_position if player else Vector2.ZERO
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_debug_label.text = "FPS: %d\nX: %.0f\nY: %.0f" % [fps, pos.x, pos.y]

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	canvas.add_child(margin)

	var bg := PanelContainer.new()
	margin.add_child(bg)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_color = Color(1, 1, 1, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	bg.add_theme_stylebox_override("panel", style)

	_debug_label = Label.new()
	_debug_label.add_theme_color_override("font_color", Color.LIME_GREEN)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	bg.add_child(_debug_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible
