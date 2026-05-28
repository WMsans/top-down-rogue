extends Node2D

var _debug_label: Label
var canvas: CanvasLayer

func _ready() -> void:
	visible = false
	_build_hud()

func _process(_delta: float) -> void:
	if not visible:
		return
	var player := get_node("../Player") as Node2D
	var pos := player.global_position if player else Vector2.ZERO
	var fps := Performance.get_monitor(Performance.TIME_FPS)

	var cave_count := get_tree().get_nodes_in_group("cave_spawned").filter(func(n): return is_instance_valid(n)).size()
	var cave_cap := 0
	var spawner := get_node_or_null("/root/LevelManager/CaveSpawner")
	if spawner:
		cave_cap = spawner.mob_cap

	var total_mobs := get_tree().get_nodes_in_group("attackable").filter(func(n): return is_instance_valid(n)).size()

	_debug_label.text = "FPS: %d\nX: %.0f\nY: %.0f\nMobs: %d / %d (total %d)" % [fps, pos.x, pos.y, cave_count, cave_cap, total_mobs]

func _build_hud() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 100

	var scale_factor := get_tree().root.get_visible_rect().size.x / get_viewport().get_visible_rect().size.x

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(4 * scale_factor))
	margin.add_theme_constant_override("margin_top", int(4 * scale_factor))
	canvas.add_child(margin)

	var bg := PanelContainer.new()
	margin.add_child(bg)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.border_color = Color(1, 1, 1, 0.3)
	style.set_border_width_all(int(1 * scale_factor))
	style.set_corner_radius_all(int(4 * scale_factor))
	style.set_content_margin_all(int(4 * scale_factor))
	bg.add_theme_stylebox_override("panel", style)

	_debug_label = Label.new()
	_debug_label.add_theme_color_override("font_color", Color.LIME_GREEN)
	_debug_label.add_theme_font_size_override("font_size", int(10 * scale_factor))
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	bg.add_child(_debug_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible = !visible
		if visible: 
			get_tree().root.add_child(canvas)
		else:
			get_tree().root.remove_child(canvas)

func _exit_tree() -> void:
	if canvas:
		if canvas.is_inside_tree():
			canvas.get_parent().remove_child(canvas)
		canvas.queue_free()
