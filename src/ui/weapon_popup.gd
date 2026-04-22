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
var _modifier_mode: bool = false
var _modifier_ref: Modifier = null
var _modifier_callback: Callable
var _modifier_tooltip: PanelContainer = null
var _card_tween: Tween = null
var _feedback_label: Label = null
var _transfer_mode: bool = false
var _transfer_slot: int = -1
var _transfer_weapon: Weapon = null
var _transfer_modifiers: Array[Modifier] = []
var _skip_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cards_container.theme = UiTheme.get_theme()
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
	_modifier_mode = false
	_pickup_weapon = new_weapon
	_pickup_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "Replace a slot:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_modifier(weapon_manager: WeaponManager, modifier: Modifier, callback: Callable) -> void:
	_modifier_mode = true
	_pickup_mode = false
	_modifier_ref = modifier
	_modifier_callback = callback
	_weapon_manager = weapon_manager
	_selected_slot = -1
	_title_label.text = "Add modifier to:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_cancel_modifier_tooltip()
	_cancel_feedback()
	_cancel_skip_button()
	_skip_button = null
	visible = false
	_weapon_manager = null
	_pickup_mode = false
	_modifier_mode = false
	_pickup_weapon = null
	_pickup_callback = Callable()
	_modifier_ref = null
	_modifier_callback = Callable()
	_selected_slot = -1
	_transfer_mode = false
	_transfer_slot = -1
	_transfer_weapon = null
	_transfer_modifiers = []
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
	if _modifier_mode and _modifier_ref != null:
		_add_modifier_header()
	var cards: Array[Control] = []
	for i in range(3):
		var weapon: Weapon = null
		if i < _weapon_manager.weapons.size():
			weapon = _weapon_manager.weapons[i]
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)
		cards.append(card)
	UiAnimations.stagger_slide_in(cards, 0.1, 20.0, 0.3)


func _add_modifier_header() -> void:
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox == null:
		return
	var icon := TextureRect.new()
	icon.texture = _modifier_ref.icon_texture
	icon.custom_minimum_size = ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)
	var name_label := Label.new()
	name_label.text = _modifier_ref.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)


func _clear_cards() -> void:
	_cancel_skip_button()
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

		_add_modifier_slots(vbox, weapon, card)

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


func _add_modifier_slots(parent: VBoxContainer, weapon: Weapon, card: PanelContainer) -> void:
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
			icon.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, icon, card))
			icon.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
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


func _on_modifier_icon_mouse_entered(modifier: Modifier, icon: Control, card: PanelContainer) -> void:
	_on_card_mouse_entered(card)
	_cancel_modifier_tooltip()
	_modifier_tooltip = PanelContainer.new()
	_modifier_tooltip.theme = UiTheme.get_theme()
	_modifier_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_modifier_tooltip.add_child(vbox)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var description := modifier.get_description()
	if description != "":
		var separator := HSeparator.new()
		vbox.add_child(separator)

		var desc_label := Label.new()
		desc_label.text = description
		desc_label.custom_minimum_size.x = TOOLTIP_MAX_WIDTH
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(desc_label)

	add_child(_modifier_tooltip)
	_position_tooltip_near(icon)


func _on_modifier_icon_mouse_exited(card: PanelContainer) -> void:
	_cancel_modifier_tooltip()
	if not card.get_global_rect().has_point(card.get_global_mouse_position()):
		_on_card_mouse_exited(card)


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
			if _transfer_mode:
				pass
			else:
				var replaced_weapon: Weapon = _weapon_manager.weapons[slot_index]
				var transferable_modifiers := _get_transferable_modifiers(replaced_weapon)
				if transferable_modifiers.size() > 0:
					_enter_transfer_mode(slot_index, replaced_weapon, transferable_modifiers)
				else:
					_pickup_callback.call(slot_index, null)
					close()
		elif _modifier_mode:
			_handle_modifier_slot_click(slot_index)
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _handle_modifier_slot_click(slot_index: int) -> void:
	var weapon: Weapon = _weapon_manager.weapons[slot_index]
	if weapon == null:
		_show_feedback("No weapon in that slot!")
		return
	var empty_slot := _find_empty_modifier_slot(weapon)
	if empty_slot == -1:
		_show_feedback("No empty modifier slots!")
		return
	_weapon_manager.add_modifier_to_weapon(slot_index, empty_slot, _modifier_ref)
	_modifier_callback.call()
	close()


func _find_empty_modifier_slot(weapon: Weapon) -> int:
	for i in range(weapon.modifier_slot_count):
		if weapon.get_modifier_at(i) == null:
			return i
	return -1


func _show_feedback(text: String) -> void:
	_cancel_feedback()
	_feedback_label = Label.new()
	_feedback_label.text = text
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_feedback_label.add_theme_font_size_override("font_size", 18)
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox:
		vbox.add_child(_feedback_label)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_feedback_label, "modulate:a", 0.0, 1.5).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN).set_delay(1.0)
		tween.tween_callback(_cancel_feedback)


func _cancel_feedback() -> void:
	if _feedback_label != null:
		_feedback_label.queue_free()
		_feedback_label = null


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


func _get_transferable_modifiers(weapon: Weapon) -> Array[Modifier]:
	var result: Array[Modifier] = []
	if weapon == null:
		return result
	for i in range(weapon.modifier_slot_count):
		var mod: Modifier = weapon.get_modifier_at(i)
		if mod != null:
			result.append(mod)
	return result


func _enter_transfer_mode(slot_index: int, replaced_weapon: Weapon, transferable_modifiers: Array[Modifier]) -> void:
	var modifier_positions: Array[Vector2] = []
	var modifier_sizes: Array[Vector2] = []
	var cards := _cards_container.get_children()
	if slot_index < cards.size():
		var card: Control = cards[slot_index]
		var slot_container: HBoxContainer = _find_modifier_slot_container(card)
		if slot_container != null:
			for child in slot_container.get_children():
				if child is TextureRect:
					modifier_positions.append(child.global_position)
					modifier_sizes.append(child.size)
	var alt_positions := _estimate_modifier_positions(transferable_modifiers.size(), modifier_positions, modifier_sizes)
	_transfer_mode = true
	_transfer_slot = slot_index
	_transfer_weapon = replaced_weapon
	_transfer_modifiers = transferable_modifiers
	_title_label.text = "Transfer a modifier?"
	_clear_cards()
	_build_transfer_cards(alt_positions)
	_add_skip_button()


func _find_modifier_slot_container(card: Control) -> HBoxContainer:
	for child in card.get_children():
		if child is VBoxContainer:
			for vbox_child in child.get_children():
				if vbox_child is HBoxContainer:
					return vbox_child
	return null


func _estimate_modifier_positions(count: int, recorded: Array[Vector2], recorded_sizes: Array[Vector2]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count == 0:
		return result
	var container_center := _cards_container.global_position + _cards_container.size * 0.5
	for i in range(count):
		if i < recorded.size():
			result.append({
				"position": recorded[i],
				"size": recorded_sizes[i],
			})
		else:
			var offset := Vector2((i - (count - 1) * 0.5) * 50.0, 0.0)
			result.append({
				"position": container_center + offset - Vector2(32, 32),
				"size": Vector2(32, 32),
			})
	return result


func _build_transfer_cards(start_positions: Array[Dictionary]) -> void:
	var cards: Array[Control] = []
	var all_labels: Array[Label] = []
	for i in range(_transfer_modifiers.size()):
		var modifier: Modifier = _transfer_modifiers[i]
		var card := _create_transfer_card(modifier, i)
		_cards_container.add_child(card)
		cards.append(card)
		var labels: Array[Label] = card.get_meta("transfer_labels")
		for label in labels:
			all_labels.append(label)
		if i < start_positions.size():
			var start_pos: Vector2 = start_positions[i]["position"]
			var start_sz: Vector2 = start_positions[i]["size"]
			var target_pos := card.global_position
			var scale_ratio := Vector2(start_sz.x / CARD_MIN_SIZE.x, start_sz.y / CARD_MIN_SIZE.y)
			card.global_position = start_pos
			card.scale = scale_ratio
			card.pivot_offset = card.size * 0.5
			var tween := card.create_tween()
			tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tween.set_parallel(true)
			tween.tween_property(card, "global_position", target_pos, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	UiAnimations.stagger_slide_in(cards, 0.08, 10.0, 0.2)
	var label_delay := 0.35 + 0.08 * max(_transfer_modifiers.size() - 1, 0)
	for label in all_labels:
		var label_tween := label.create_tween()
		label_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		label_tween.tween_property(label, "modulate:a", 1.0, 0.25).set_delay(label_delay).set_trans(Tween.TRANS_LINEAR)


func _create_transfer_card(modifier: Modifier, index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.gui_input.connect(_on_transfer_card_input.bind(index))
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

	if modifier.icon_texture != null:
		var icon := TextureRect.new()
		icon.texture = modifier.icon_texture
		icon.custom_minimum_size = ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	else:
		var fallback := ColorRect.new()
		fallback.custom_minimum_size = ICON_SIZE
		fallback.color = Color(0.212, 0.110, 0.133, 1)
		vbox.add_child(fallback)

	var name_label := Label.new()
	name_label.text = modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.modulate.a = 0.0
	vbox.add_child(name_label)

	var text_labels: Array[Label] = [name_label]

	var desc_text := modifier.get_description()
	if desc_text != "":
		var desc_label := Label.new()
		desc_label.text = desc_text
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 24.0
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.modulate.a = 0.0
		vbox.add_child(desc_label)
		text_labels.append(desc_label)

	card.set_meta("transfer_labels", text_labels)

	return card


func _on_transfer_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var chosen_modifier: Modifier = _transfer_modifiers[index]
		_pickup_callback.call(_transfer_slot, chosen_modifier)
		close()


func _add_skip_button() -> void:
	_cancel_skip_button()
	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_button.theme = UiTheme.get_theme()
	_skip_button.pressed.connect(_on_skip_pressed)
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox:
		vbox.add_child(_skip_button)
		var skip_delay := 0.35 + 0.08 * max(_transfer_modifiers.size() - 1, 0) + 0.4
		UiAnimations.fade_in(_skip_button, 0.3, skip_delay)


func _on_skip_pressed() -> void:
	_pickup_callback.call(_transfer_slot, null)
	close()


func _cancel_skip_button() -> void:
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null
