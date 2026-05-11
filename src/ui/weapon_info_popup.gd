class_name WeaponInfoPopup
extends CanvasLayer

const POPUP_OFFSET_Y: float = -24.0
const SHOW_DURATION: float = 0.35
const HIDE_DURATION: float = 0.20
const CROSSFADE_DURATION: float = 0.10

var _card_root: Control
var _panel: PanelContainer
var _name_label: Label
var _damage_label: Label
var _cooldown_label: Label
var _modifier_container: HBoxContainer
var _show_tween: Tween
var _hide_tween: Tween
var _crossfade_tween: Tween
var _is_visible: bool = false
var _current_drop: WeaponDrop = null
var _pending_hide: bool = false


func _ready() -> void:
	layer = 15

	_card_root = Control.new()
	_card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_root)

	_panel = PanelContainer.new()
	_panel.theme = UiTheme.get_theme()
	_card_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_name_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_damage_label = Label.new()
	_damage_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_damage_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_damage_label)

	_cooldown_label = Label.new()
	_cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	_cooldown_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_cooldown_label)

	_modifier_container = HBoxContainer.new()
	vbox.add_child(_modifier_container)

	_card_root.hide()
	_card_root.modulate.a = 0.0


func show_for(drop: WeaponDrop) -> void:
	_pending_hide = false
	if not is_instance_valid(drop):
		dismiss()
		return
	var weapon: Weapon = drop.weapon
	if weapon == null:
		dismiss()
		return

	if _current_drop == drop and _is_visible:
		return

	if _crossfade_tween and _crossfade_tween.is_valid():
		return

	if _is_visible and _current_drop != drop:
		_crossfade_to(drop)
		return

	_current_drop = drop
	_populate(weapon)
	_animate_show()


func dismiss() -> void:
	if not _is_visible:
		if _show_tween and _show_tween.is_valid():
			_show_tween.kill()
		_pending_hide = true
		return
	_animate_hide()


func is_shown() -> bool:
	return _is_visible


func update_position(drop: WeaponDrop) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var screen_pos := cam.get_canvas_transform() * drop.global_position
	screen_pos.y += POPUP_OFFSET_Y
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _card_root.size
	const MARGIN := 8.0
	screen_pos.x = clampf(screen_pos.x, MARGIN, viewport_size.x - panel_size.x - MARGIN)
	screen_pos.y = clampf(screen_pos.y, MARGIN, viewport_size.y - panel_size.y - MARGIN)
	_card_root.position = screen_pos


func _populate(weapon: Weapon) -> void:
	_name_label.text = weapon.name
	_damage_label.text = "Damage: %.0f" % weapon.damage
	_cooldown_label.text = "Cooldown: %.1fs" % weapon.cooldown

	for child in _modifier_container.get_children():
		_modifier_container.remove_child(child)
		child.queue_free()

	var has_modifier := false
	for i in range(weapon.modifier_slot_count):
		var mod := weapon.get_modifier_at(i)
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(24, 24)
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if mod and mod.icon_texture:
			slot.texture = mod.icon_texture
			has_modifier = true
		_modifier_container.add_child(slot)

	_modifier_container.visible = has_modifier


func _animate_show() -> void:
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	_card_root.show()
	_card_root.modulate.a = 0.0
	_card_root.scale = Vector2(0.9, 0.9)

	if _current_drop:
		update_position(_current_drop)

	var target_y := _card_root.position.y
	_card_root.position.y += 12.0

	_show_tween = create_tween()
	_show_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_show_tween.parallel().tween_property(_card_root, "position:y", target_y, SHOW_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_tween.parallel().tween_property(_card_root, "modulate:a", 1.0, 0.22)\
		.set_trans(Tween.TRANS_LINEAR)
	_show_tween.parallel().tween_property(_card_root, "scale", Vector2.ONE, SHOW_DURATION)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_show_tween.tween_callback(func() -> void: _is_visible = true)


func _animate_hide() -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	_is_visible = false
	_current_drop = null
	_pending_hide = false

	_hide_tween = create_tween()
	_hide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hide_tween.parallel().tween_property(_card_root, "modulate:a", 0.0, 0.15)\
		.set_trans(Tween.TRANS_LINEAR)
	_hide_tween.parallel().tween_property(_card_root, "position:y", _card_root.position.y + 8.0, HIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_hide_tween.tween_callback(func() -> void: _card_root.hide())


func _crossfade_to(drop: WeaponDrop) -> void:
	if _show_tween and _show_tween.is_valid():
		_show_tween.kill()
	if _hide_tween and _hide_tween.is_valid():
		_hide_tween.kill()

	_is_visible = false

	_crossfade_tween = create_tween()
	_crossfade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_crossfade_tween.tween_property(_card_root, "modulate:a", 0.0, CROSSFADE_DURATION)
	_crossfade_tween.tween_callback(func() -> void:
		_current_drop = drop
		_populate(drop.weapon)
		if _pending_hide:
			_pending_hide = false
			_animate_hide()
		else:
			_animate_show()
	)
