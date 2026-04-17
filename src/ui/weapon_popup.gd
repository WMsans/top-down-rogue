extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 220)
const ICON_SIZE := Vector2(96, 96)
const MODIFIER_ICON_SIZE := Vector2(32, 32)
const TOOLTIP_MAX_WIDTH := 180

const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

@onready var _overlay: ColorRect = %Overlay
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _title_label: Label = %TitleLabel

var _weapon_manager: WeaponManager = null
var _selected_slot: int = -1
var _pickup_mode: bool = false
var _pickup_weapon: Weapon = null
var _pickup_callback: Callable
var _modifier_tooltip: PanelContainer = null
var _card_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	_title_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_constant_override("outline_size", 2)
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	visible = false
	_overlay.gui_input.connect(_on_overlay_input)


func open(weapon_manager: WeaponManager) -> void:
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "WEAPONS"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_pickup(weapon_manager: WeaponManager, new_weapon: Weapon, callback: Callable) -> void:
	_pickup_mode = true
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "Replace a slot:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_cancel_modifier_tooltip()
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_selected_slot = -1
	_clear_cards()
	SceneManager.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build_cards() -> void:
	_clear_cards()
	var cards: Array[Control] = []
	for i in range(3):
		var weapon: Weapon = null
		if i < _weapon_manager.weapons.size():
			weapon = _weapon_manager.weapons[i]
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)
		cards.append(card)
	UiAnimations.stagger_slide_in(cards, 0.1, 20.0, 0.3)


func _clear_cards() -> void:
	for child in _cards_container.get_children():
		child.queue_free()


func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_card_input.bind(slot_index))
	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if weapon == null:
		var empty_label := Label.new()
		empty_label.text = "EMPTY"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		vbox.add_child(empty_label)
	else:
		_add_icon(vbox, weapon)
		var name_label := Label.new()
		name_label.text = weapon.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		vbox.add_child(name_label)

		var stats := weapon.get_base_stats()
		var cooldown_label := Label.new()
		cooldown_label.text = "Cooldown: %.1fs" % stats["cooldown"]
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		cooldown_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(cooldown_label)

		var damage_label := Label.new()
		damage_label.text = "Damage: %.0f" % stats["damage"]
		damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		damage_label.add_theme_color_override("font_color", UiTheme.ACCENT)
		damage_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(damage_label)

		_add_modifier_slots(vbox, weapon)

	return card


func _add_icon(parent: VBoxContainer, weapon: Weapon) -> void:
	if weapon.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = weapon.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		parent.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.212, 0.110, 0.133, 1)
		parent.add_child(fallback)
		var q_label := Label.new()
		q_label.text = "?"
		q_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q_label.anchors_preset = Control.PRESET_FULL_RECT
		q_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		fallback.add_child(q_label)


func _add_modifier_slots(parent: VBoxContainer, weapon: Weapon) -> void:
	var slot_container := HBoxContainer.new()
	slot_container.add_theme_constant_override("separation", 4)
	slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(slot_container)

	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier != null:
			var icon := TextureRect.new()
			icon.custom_minimum_size = MODIFIER_ICON_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if modifier.icon_texture != null:
				icon.texture = modifier.icon_texture
			else:
				icon.texture = null
			icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon.gui_input.connect(_on_modifier_icon_input.bind(modifier, icon))
			icon.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, icon))
			icon.mouse_exited.connect(_on_modifier_icon_mouse_exited)
			slot_container.add_child(icon)
		else:
			var empty_slot := ColorRect.new()
			empty_slot.custom_minimum_size = MODIFIER_ICON_SIZE
			empty_slot.color = Color(0.165, 0.082, 0.098, 1)
			slot_container.add_child(empty_slot)


func _on_card_mouse_entered(card: PanelContainer) -> void:
	if card.material is ShaderMaterial:
		card.material.set_shader_parameter("glow_enabled", true)
	var tween := card.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(card, "scale", Vector2(1.03, 1.03), 0.15).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
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
	if _selected_slot == -1:
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = UiTheme.PANEL_BORDER
			card.add_theme_stylebox_override("panel", new_style)


func _on_modifier_icon_mouse_entered(modifier: Modifier, icon: Control) -> void:
	_cancel_modifier_tooltip()
	_modifier_tooltip = PanelContainer.new()
	_modifier_tooltip.custom_minimum_size.x = TOOLTIP_MAX_WIDTH

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_modifier_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var desc_label := Label.new()
	desc_label.text = modifier.get_description()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	desc_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(desc_label)

	add_child(_modifier_tooltip)
	_position_tooltip_near(icon)


func _on_modifier_icon_mouse_exited() -> void:
	_cancel_modifier_tooltip()


func _on_modifier_icon_input(_event: InputEvent, _modifier: Modifier, _icon: Control) -> void:
	pass


func _position_tooltip_near(icon: Control) -> void:
	if _modifier_tooltip == null:
		return
	await get_tree().process_frame
	var icon_rect := icon.get_global_rect()
	var tooltip_size := _modifier_tooltip.get_combined_minimum_size()
	var pos_x := icon_rect.position.x + icon_rect.size.x / 2.0 - tooltip_size.x / 2.0
	var viewport_width := get_viewport().get_visible_rect().size.x
	pos_x = clampf(pos_x, 4.0, viewport_width - tooltip_size.x - 4.0)
	_modifier_tooltip.global_position = Vector2(
		pos_x,
		icon_rect.position.y - tooltip_size.y - 4.0
	)
	_modifier_tooltip.size = tooltip_size


func _cancel_modifier_tooltip() -> void:
	if _modifier_tooltip != null:
		_modifier_tooltip.queue_free()
		_modifier_tooltip = null


func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			_pickup_callback.call(slot_index)
			close()
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _highlight_slot(slot_index: int) -> void:
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		var style := card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			var new_style := style.duplicate() as StyleBoxFlat
			new_style.border_color = UiTheme.ACCENT_GOLD
			card.add_theme_stylebox_override("panel", new_style)
		var tween := card.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(card, "modulate", Color(1.0, 0.85, 0.5, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _swap_weapons(slot_a: int, slot_b: int) -> void:
	if _weapon_manager != null:
		_weapon_manager.swap_weapons(slot_a, slot_b)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			close()