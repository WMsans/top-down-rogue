class_name Card
extends Control

signal card_clicked

@export var card_size: Vector2 = Vector2(160, 220):
	set(v):
		card_size = v
		if is_node_ready():
			custom_minimum_size = card_size
			_update_subviewport()

@export var icon_size: Vector2 = Vector2(96, 96)
@export var mod_icon_size: Vector2 = Vector2(32, 32)
@export var tilt_max: float = 12.0
@export var hover_scale_target: float = 1.12
@export var is_selectable: bool = true

@onready var _shadow: Control = $Shadow
@onready var _shadow_rect: ColorRect = $Shadow/ShadowRect
@onready var _subviewport_container: SubViewportContainer = $SubViewportContainer
@onready var _subviewport: SubViewport = $SubViewportContainer/SubViewport
@onready var _card_panel: PanelContainer = $SubViewportContainer/SubViewport/CardPanel
@onready var _content_vbox: VBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox
@onready var _icon: TextureRect = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/Icon
@onready var _name_label: Label = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/NameLabel
@onready var _stats_container: VBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/StatsContainer
@onready var _modifier_slots: HBoxContainer = $SubViewportContainer/SubViewport/CardPanel/ContentVBox/ModifierSlots

var _is_hovered: bool = false
var _is_selected: bool = false
var _hover_tween: Tween
var _exit_tween: Tween
var _click_tween: Tween
var _current_tilt: Vector2 = Vector2.ZERO
var _orig_z_index: int = 0
var _tilt_was_active: bool = false

func _ready() -> void:
	custom_minimum_size = card_size
	pivot_offset = card_size / 2.0
	_orig_z_index = z_index
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_setup_shadow()
	set_process(true)

func _setup_shadow() -> void:
	_shadow.position = Vector2(6, 6)
	_shadow_rect.custom_minimum_size = card_size
	_shadow_rect.color = Color(0, 0, 0, 0.12)

func populate(icon_texture: Texture2D, card_name: String, stats: Array[String] = [], modifier_icons: Array[Texture2D] = []) -> void:
	if icon_texture:
		_icon.texture = icon_texture
		_icon.custom_minimum_size = icon_size
		_icon.show()
	else:
		_icon.hide()

	_name_label.text = card_name

	for child in _stats_container.get_children():
		child.queue_free()
	if stats.size() > 0:
		_stats_container.show()
		for stat_text in stats:
			var label := Label.new()
			label.text = stat_text
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
			label.add_theme_font_size_override("font_size", 14)
			_stats_container.add_child(label)
	else:
		_stats_container.hide()

	for child in _modifier_slots.get_children():
		child.queue_free()
	if modifier_icons.size() > 0:
		_modifier_slots.show()
		for mod_tex in modifier_icons:
			var slot := TextureRect.new()
			slot.custom_minimum_size = mod_icon_size
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if mod_tex:
				slot.texture = mod_tex
			_modifier_slots.add_child(slot)
	else:
		_modifier_slots.hide()

	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_selected(selected: bool) -> void:
	if not is_selectable:
		return
	_is_selected = selected
	_update_border_color()

func _update_border_color() -> void:
	if not is_instance_valid(_card_panel):
		return
	var style := _card_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if not style:
		return
	var new_style := style.duplicate() as StyleBoxFlat
	if _is_selected:
		new_style.border_color = UiTheme.ACCENT_GOLD
	elif _is_hovered:
		new_style.border_color = UiTheme.ACCENT
	else:
		new_style.border_color = UiTheme.PANEL_BORDER
	_card_panel.add_theme_stylebox_override("panel", new_style)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_name_color(color: Color) -> void:
	_name_label.add_theme_color_override("font_color", color)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_name_font_size(size: int) -> void:
	_name_label.add_theme_font_size_override("font_size", size)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _process(_delta: float) -> void:
	var mouse_pos := get_local_mouse_position()
	var mouse_in_card := mouse_pos.x >= 0.0 and mouse_pos.x <= card_size.x and mouse_pos.y >= 0.0 and mouse_pos.y <= card_size.y
	if mouse_in_card != _is_hovered:
		if mouse_in_card:
			_is_hovered = true
			z_index = 10
			_animate_hover_enter()
			_update_border_color()
			_tilt_was_active = true
		else:
			_is_hovered = false
			z_index = _orig_z_index
			_animate_hover_exit()
			_update_border_color()
			if _tilt_was_active:
				var start_tilt := _current_tilt
				var tilt_tween := create_tween()
				tilt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				tilt_tween.tween_method(func(val: Vector2): _set_tilt_angles(val), start_tilt, Vector2.ZERO, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_tilt_was_active = false

	if _is_hovered:
		var ratio_x := clampf(mouse_pos.x / card_size.x, 0.0, 1.0)
		var ratio_y := clampf(mouse_pos.y / card_size.y, 0.0, 1.0)
		var x_rot := lerpf(-tilt_max, tilt_max, ratio_y)
		var y_rot := lerpf(-tilt_max, tilt_max, ratio_x)
		_set_tilt_angles(Vector2(x_rot, y_rot))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_hovered and is_selectable:
			_play_click_feedback()
			card_clicked.emit()

func _animate_hover_enter() -> void:
	if _exit_tween and _exit_tween.is_running():
		_exit_tween.kill()
	if _hover_tween and _hover_tween.is_running():
		return
	_hover_tween = create_tween()
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tween.tween_property(self, "scale", Vector2(hover_scale_target, hover_scale_target), 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(10, 10), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_hover_exit() -> void:
	if _hover_tween and _hover_tween.is_running():
		_hover_tween.kill()
	_exit_tween = create_tween()
	_exit_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_exit_tween.tween_property(self, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	var shadow_tween := create_tween()
	shadow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	shadow_tween.tween_property(_shadow, "position", Vector2(6, 6), 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _play_click_feedback() -> void:
	if _click_tween and _click_tween.is_running():
		_click_tween.kill()
	var current_scale := scale
	_click_tween = create_tween()
	_click_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_click_tween.tween_property(self, "scale", current_scale * 0.97, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_click_tween.tween_property(self, "scale", current_scale, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _set_tilt_angles(angles: Vector2) -> void:
	_current_tilt = angles
	var mat := _subviewport_container.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("x_rot", angles.x)
		mat.set_shader_parameter("y_rot", angles.y)

func _update_subviewport() -> void:
	if is_node_ready():
		_subviewport.size = Vector2i(int(card_size.x), int(card_size.y))
		if _subviewport_container.material is ShaderMaterial:
			_subviewport_container.material.set_shader_parameter("rect_size", card_size)
		_shadow_rect.custom_minimum_size = card_size
		_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE
