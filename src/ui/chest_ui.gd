# src/ui/chest_ui.gd
class_name ChestUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 240)
const ICON_SIZE := Vector2(72, 72)
const CARD_SCENE := preload("res://scenes/ui/card.tscn")

var _weapons: Array[Weapon] = []
var _callback: Callable
var _chosen: bool = false
var _is_closing: bool = false
var _card_slots: Array[Control] = []

@onready var _title_label: Label = %TitleLabel
@onready var _card_container: HBoxContainer = %CardContainer
@onready var _skip_button: Button = %SkipButton
@onready var _panel_container: PanelContainer = %ShopPanel
@onready var _header_bar: PanelContainer = %HeaderBar
@onready var _action_bar: PanelContainer = %ActionBar
@onready var _overlay: ColorRect = %Overlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_skip_button.pressed.connect(close)
	_overlay.gui_input.connect(_on_overlay_input)
	UiAnimations.setup_button_hover(_skip_button)
	_style_header()
	_style_action_bar()
	_style_skip_button()
	visible = false


func _style_header() -> void:
	_title_label.add_theme_font_override("font", UiTheme.PIXEL_FONT)
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_title_label.add_theme_font_size_override("font_size", 32)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = UiTheme.SURFACE_BG
	header_style.set_corner_radius_all(0)
	header_style.set_corner_radius(CORNER_TOP_LEFT, 6)
	header_style.set_corner_radius(CORNER_TOP_RIGHT, 6)
	header_style.border_color = UiTheme.ACCENT
	header_style.set_border_width_all(0)
	header_style.set_border_width(SIDE_BOTTOM, 2)
	header_style.content_margin_top = 14
	header_style.content_margin_bottom = 14
	header_style.content_margin_left = 24
	header_style.content_margin_right = 24
	header_style.shadow_color = Color(0, 0, 0, 0)
	_header_bar.add_theme_stylebox_override("panel", header_style)


func _style_action_bar() -> void:
	var action_style := StyleBoxFlat.new()
	action_style.bg_color = UiTheme.SURFACE_BG
	action_style.set_corner_radius_all(0)
	action_style.set_corner_radius(CORNER_BOTTOM_LEFT, 6)
	action_style.set_corner_radius(CORNER_BOTTOM_RIGHT, 6)
	action_style.border_color = UiTheme.PANEL_BORDER
	action_style.set_border_width_all(0)
	action_style.set_border_width(SIDE_TOP, 1)
	action_style.content_margin_top = 12
	action_style.content_margin_bottom = 12
	action_style.content_margin_left = 16
	action_style.content_margin_right = 16
	action_style.shadow_color = Color(0, 0, 0, 0)
	_action_bar.add_theme_stylebox_override("panel", action_style)


func _style_skip_button() -> void:
	var theme := UiTheme.get_theme()
	_skip_button.theme = theme
	_skip_button.add_theme_font_size_override("font_size", 18)
	_skip_button.custom_minimum_size = Vector2(180, 40)


func open_with_weapons(weapons: Array[Weapon], callback: Callable) -> void:
	_weapons = weapons
	_callback = callback
	_chosen = false
	_is_closing = false
	_title_label.text = "Choose a Weapon"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true
	_play_entrance_animation()


func close() -> void:
	if _is_closing:
		return
	_is_closing = true
	await _play_exit_animation()
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if not _chosen and _callback.is_valid():
		_callback.call(null)


func _play_entrance_animation() -> void:
	_overlay.modulate.a = 0.0
	_panel_container.modulate.a = 0.0
	_panel_container.pivot_offset = _panel_container.size * 0.5
	_panel_container.scale = Vector2(0.92, 0.92)
	_panel_container.position.y += 30

	var overlay_tween := create_tween()
	overlay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	overlay_tween.tween_property(_overlay, "modulate:a", 1.0, 0.18)

	var panel_tween := create_tween()
	panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel_tween.set_parallel(true)
	panel_tween.tween_property(_panel_container, "modulate:a", 1.0, 0.22)
	panel_tween.tween_property(_panel_container, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	panel_tween.tween_property(_panel_container, "position:y", _panel_container.position.y - 30, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_stagger_cards_in()


func _stagger_cards_in() -> void:
	for i in _card_slots.size():
		var slot := _card_slots[i]
		slot.modulate.a = 0.0
		slot.position.y += 24
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(0.12 + i * 0.08)
		tween.parallel().tween_property(slot, "modulate:a", 1.0, 0.28)
		tween.parallel().tween_property(slot, "position:y", slot.position.y - 24, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_exit_animation() -> void:
	var overlay_tween := create_tween()
	overlay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	overlay_tween.tween_property(_overlay, "modulate:a", 0.0, 0.18)

	var panel_tween := create_tween()
	panel_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	panel_tween.set_parallel(true)
	panel_tween.tween_property(_panel_container, "modulate:a", 0.0, 0.18)
	panel_tween.tween_property(_panel_container, "scale", Vector2(0.94, 0.94), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await panel_tween.finished


func _build_cards() -> void:
	_clear_cards()
	for i in _weapons.size():
		var weapon: Weapon = _weapons[i]
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_theme_constant_override("separation", 4)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var card := _create_weapon_card(weapon, i)
		slot.add_child(card)
		card.ready.connect(func():
			var stats: Array[String] = []
			var base_stats := weapon.get_base_stats()
			stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
			stats.append("Damage: %.0f" % base_stats["damage"])
			card.populate(weapon.icon_texture, weapon.name, stats)
		, CONNECT_ONE_SHOT)
		_card_container.add_child(slot)
		_card_slots.append(slot)


func _clear_cards() -> void:
	for child in _card_container.get_children():
		child.queue_free()
	_card_slots.clear()


func _create_weapon_card(weapon: Weapon, index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	card.card_size = CARD_MIN_SIZE
	card.icon_size = ICON_SIZE
	card.card_clicked.connect(func(): _select_weapon(index))
	return card


func _select_weapon(index: int) -> void:
	if _is_closing:
		return
	if index < 0 or index >= _weapons.size():
		return
	_chosen = true
	_is_closing = true
	var weapon: Weapon = _weapons[index]
	await _play_exit_animation()
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if _callback.is_valid():
		_callback.call(weapon)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
