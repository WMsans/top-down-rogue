# src/ui/chest_ui.gd
class_name ChestUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(140, 210)
const ICON_SIZE := Vector2(64, 64)
const CARD_SCENE := preload("res://scenes/ui/card.tscn")

var _weapons: Array[Weapon] = []
var _callback: Callable
var _chosen: bool = false
var _card_slots: Array[Control] = []

@onready var _overlay: ColorRect = %Overlay
@onready var _title_label: Label = %TitleLabel
@onready var _card_container: HBoxContainer = %CardContainer
@onready var _skip_button: Button = %SkipButton
@onready var _panel_container: PanelContainer = %ShopPanel
@onready var _header_bar: PanelContainer = %HeaderBar
@onready var _action_bar: PanelContainer = %ActionBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.gui_input.connect(_on_overlay_input)
	_skip_button.pressed.connect(close)
	UiAnimations.setup_button_hover(_skip_button)
	_style_header()
	_style_action_bar()
	_style_skip_button()
	visible = false


func _style_header() -> void:
	_title_label.add_theme_font_override("font", UiTheme.PIXEL_FONT)
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_title_label.add_theme_font_size_override("font_size", 28)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = UiTheme.SURFACE_BG
	header_style.set_corner_radius_all(0)
	header_style.set_corner_radius(CORNER_TOP_LEFT, 6)
	header_style.set_corner_radius(CORNER_TOP_RIGHT, 6)
	header_style.border_color = UiTheme.ACCENT
	header_style.set_border_width_all(0)
	header_style.set_border_width(SIDE_BOTTOM, 2)
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
	action_style.shadow_color = Color(0, 0, 0, 0)
	_action_bar.add_theme_stylebox_override("panel", action_style)


func _style_skip_button() -> void:
	var theme := UiTheme.get_theme()
	_skip_button.theme = theme
	_skip_button.add_theme_font_size_override("font_size", 16)
	_skip_button.custom_minimum_size = Vector2(0, 36)


func open_with_weapons(weapons: Array[Weapon], callback: Callable) -> void:
	_weapons = weapons
	_callback = callback
	_chosen = false
	_title_label.text = "Choose a Weapon"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true
	_play_entrance_animation()


func close() -> void:
	_clear_cards()
	visible = false
	SceneManager.set_paused(false)
	if not _chosen and _callback.is_valid():
		_callback.call(null)


func _play_entrance_animation() -> void:
	_header_bar.modulate.a = 0.0
	_action_bar.modulate.a = 0.0
	var header_tween := _header_bar.create_tween()
	header_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	header_tween.tween_property(_header_bar, "modulate:a", 1.0, 0.2)

	var action_tween := _action_bar.create_tween()
	action_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	action_tween.tween_interval(0.1)
	action_tween.tween_property(_action_bar, "modulate:a", 1.0, 0.2)

	var cards: Array[Control] = []
	for child in _card_container.get_children():
		var slot := child as Control
		if slot:
			slot.position.y += 20
			slot.modulate.a = 0.0
			cards.append(slot)
	for i in cards.size():
		var tween_card := cards[i].create_tween()
		tween_card.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween_card.tween_interval(0.08 * i)
		tween_card.parallel().tween_property(cards[i], "position:y", cards[i].position.y - 20, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tween_card.parallel().tween_property(cards[i], "modulate:a", 1.0, 0.3)


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
	if index < 0 or index >= _weapons.size():
		return
	_chosen = true
	var weapon: Weapon = _weapons[index]
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
