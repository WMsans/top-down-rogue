# src/ui/chest_ui.gd
class_name ChestUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(140, 210)
const ICON_SIZE := Vector2(64, 64)
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

var _weapons: Array[Weapon] = []
var _callback: Callable
var _chosen: bool = false
var _card_slots: Array[Control] = []

@onready var _overlay: ColorRect = %Overlay
@onready var _title_label: Label = %TitleLabel
@onready var _card_container: HBoxContainer = %CardContainer
@onready var _close_button: Button = %CloseButton
@onready var _panel_container: PanelContainer = %ShopPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.gui_input.connect(_on_overlay_input)
	_close_button.pressed.connect(close)
	UiAnimations.setup_button_hover(_close_button)
	_style_header()
	visible = false


func _style_header() -> void:
	_title_label.add_theme_font_override("font", UiTheme.PIXEL_FONT)
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_title_label.add_theme_font_size_override("font_size", 28)


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
	_panel_container.modulate.a = 0.0
	var tween := _panel_container.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_panel_container, "modulate:a", 1.0, 0.25)

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
		_card_container.add_child(slot)
		_card_slots.append(slot)


func _clear_cards() -> void:
	for child in _card_container.get_children():
		child.queue_free()
	_card_slots.clear()
	_price_labels.clear()


func _create_weapon_card(weapon: Weapon, index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
	card.gui_input.connect(_on_card_gui_input.bind(index, card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon.icon_texture:
		var icon_container := CenterContainer.new()
		icon_container.custom_minimum_size = ICON_SIZE * 1.5
		vbox.add_child(icon_container)

		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(icon)
	else:
		var fallback := CenterContainer.new()
		fallback.custom_minimum_size = ICON_SIZE * 1.5
		vbox.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		fallback.add_child(q_label)

	var name_label := Label.new()
	name_label.text = weapon.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var stats := weapon.get_base_stats()
	var cooldown_label := Label.new()
	cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	cooldown_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(cooldown_label)

	var damage_label := Label.new()
	damage_label.text = "Damage: %.0f" % stats["damage"]
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	damage_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(damage_label)

	return card


func _on_card_mouse_entered(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", true)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.ACCENT
		card.add_theme_stylebox_override("panel", new_style)


func _on_card_mouse_exited(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", false)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.PANEL_BORDER
		card.add_theme_stylebox_override("panel", new_style)


func _on_card_gui_input(event: InputEvent, index: int, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_weapon(index)


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