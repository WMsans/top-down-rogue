extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 220)
const ICON_SIZE := Vector2(96, 96)
const MODIFIER_ICON_SIZE := Vector2(32, 32)
const TOOLTIP_MAX_WIDTH := 180

const CARD_SCENE := preload("res://scenes/ui/card.tscn")

@onready var _overlay: ColorRect = %Overlay
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _title_label: Label = %TitleLabel

var _weapon_manager: WeaponManager = null
var _inventory: PlayerInventory = null
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
var _pickup_header_elements: Array[Control] = []
var _skip_button: Button = null
var _remove_mode: bool = false
var _remove_callback: Callable
var _remove_weapon: Weapon = null
var _modifier_header_elements: Array[Control] = []
var _transfer_card_nodes: Array[Control] = []
var _transfer_placeholders: Array[Control] = []


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
	var player := get_tree().get_first_node_in_group("player")
	_inventory = player.get_node_or_null("PlayerInventory") if player else null
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
	var player := get_tree().get_first_node_in_group("player")
	_inventory = player.get_node_or_null("PlayerInventory") if player else null
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
	var player := get_tree().get_first_node_in_group("player")
	_inventory = player.get_node_or_null("PlayerInventory") if player else null
	_selected_slot = -1
	_title_label.text = "Add modifier to:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_remove(weapon_manager: WeaponManager, callback: Callable) -> void:
	_remove_mode = true
	_modifier_mode = false
	_pickup_mode = false
	_remove_callback = callback
	_weapon_manager = weapon_manager
	var player := get_tree().get_first_node_in_group("player")
	_inventory = player.get_node_or_null("PlayerInventory") if player else null
	_remove_weapon = null
	_selected_slot = -1
	_title_label.text = "Remove modifier from:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func open_for_inventory_modifier(weapon_manager: WeaponManager, player_inventory: PlayerInventory, modifier: Modifier, callback: Callable) -> void:
	_modifier_mode = true
	_pickup_mode = false
	_modifier_ref = modifier
	_modifier_callback = callback
	_weapon_manager = weapon_manager
	var player := get_tree().get_first_node_in_group("player")
	_inventory = player.get_node_or_null("PlayerInventory") if player else null
	_selected_slot = -1
	set_meta("player_inventory_ref", player_inventory)
	_title_label.text = "Equip modifier to:"
	_build_cards()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_cancel_modifier_tooltip()
	_cancel_feedback()
	_cancel_skip_button()
	_clear_pickup_header()
	_clear_modifier_header()
	_skip_button = null
	visible = false
	_weapon_manager = null
	_inventory = null
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
	_remove_mode = false
	_remove_callback = Callable()
	_remove_weapon = null
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
	if _pickup_mode and _pickup_weapon != null:
		_add_pickup_header()
	if _modifier_mode and _modifier_ref != null:
		_add_modifier_header()
	var cards: Array[Control] = []
	for i in range(PlayerInventory.MAX_WEAPON_SLOTS):
		var weapon: Weapon = null
		if _inventory:
			weapon = _inventory.get_weapon(i)
		var card := _create_card(weapon, i)
		_cards_container.add_child(card)
		cards.append(card)
	UiAnimations.stagger_slide_in(cards, 0.1, 20.0, 0.3)


func _add_modifier_header() -> void:
	_clear_modifier_header()
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox == null:
		return
	var icon := TextureRect.new()
	icon.texture = _modifier_ref.icon_texture
	icon.custom_minimum_size = ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var title_index := (%TitleLabel as Node).get_index()
	vbox.add_child(icon)
	vbox.move_child(icon, title_index + 1)
	_modifier_header_elements.append(icon)
	var name_label := Label.new()
	name_label.text = _modifier_ref.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)
	vbox.move_child(name_label, title_index + 2)
	_modifier_header_elements.append(name_label)


func _add_pickup_header() -> void:
	_clear_pickup_header()
	if _pickup_weapon == null:
		return
	var vbox := %CardsContainer.get_parent() as VBoxContainer
	if vbox == null:
		return
	var title_index := (%TitleLabel as Node).get_index()

	var header_label := Label.new()
	header_label.text = "New weapon:"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	header_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header_label)
	vbox.move_child(header_label, title_index + 1)
	_pickup_header_elements.append(header_label)

	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var base_stats := _pickup_weapon.get_base_stats()
	stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
	stats.append("Damage: %.0f" % base_stats["damage"])
	card.populate(_pickup_weapon.icon_texture, _pickup_weapon.name, stats)
	card.set_selected(true)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	vbox.add_child(card)
	vbox.move_child(card, title_index + 2)
	_pickup_header_elements.append(card)


func _clear_pickup_header() -> void:
	for element in _pickup_header_elements:
		if is_instance_valid(element):
			element.queue_free()
	_pickup_header_elements.clear()


func _clear_cards() -> void:
	_cancel_skip_button()
	_clear_pickup_header()
	_clear_modifier_header()
	for card in _transfer_card_nodes:
		if is_instance_valid(card):
			card.queue_free()
	_transfer_card_nodes.clear()
	for placeholder in _transfer_placeholders:
		if is_instance_valid(placeholder):
			placeholder.queue_free()
	_transfer_placeholders.clear()
	for child in _cards_container.get_children():
		child.queue_free()


func _create_card(weapon: Weapon, slot_index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	if weapon == null:
		card.populate(null, "EMPTY")
	else:
		var stats: Array[String] = []
		var base_stats := weapon.get_base_stats()
		stats.append("Cooldown: %.1fs" % base_stats["cooldown"])
		stats.append("Damage: %.0f" % base_stats["damage"])
		var mod_icons: Array[Texture2D] = []
		for i in range(weapon.modifier_slot_count):
			var mod: Modifier = weapon.get_modifier_at(i)
			mod_icons.append(mod.icon_texture if mod else null)
		card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)
		_add_modifier_slots_to_card(card, weapon)
	card.card_clicked.connect(_on_card_input.bind(slot_index))
	card.is_selectable = true
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


func _add_modifier_slots_to_card(card: Card, weapon: Weapon) -> void:
	var overlay := HBoxContainer.new()
	overlay.add_theme_constant_override("separation", 4)
	overlay.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		var btn := TextureButton.new()
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = MODIFIER_ICON_SIZE
		if modifier != null and modifier.icon_texture != null:
			btn.texture_normal = modifier.icon_texture
		else:
			btn.texture_normal = null
		btn.mouse_entered.connect(_on_modifier_icon_mouse_entered.bind(modifier, btn, card))
		btn.mouse_exited.connect(_on_modifier_icon_mouse_exited.bind(card))
		overlay.add_child(btn)
	card.add_child(overlay)
	overlay.position = Vector2(12, card.card_size.y - MODIFIER_ICON_SIZE.y - 8)
	overlay.size.x = card.card_size.x - 24


func _on_modifier_icon_mouse_entered(modifier: Modifier, icon: Control, card: Control) -> void:
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


func _on_modifier_icon_mouse_exited(card: Control) -> void:
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


func _clear_modifier_header() -> void:
	for element in _modifier_header_elements:
		if is_instance_valid(element):
			element.queue_free()
	_modifier_header_elements.clear()


func _on_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _pickup_mode:
			if _transfer_mode:
				pass
			else:
				var replaced_weapon: Weapon = _inventory.get_weapon(slot_index)
				var transferable_modifiers := _get_transferable_modifiers(replaced_weapon)
				if transferable_modifiers.size() > 0:
					_enter_transfer_mode(slot_index, replaced_weapon, transferable_modifiers)
				else:
					_pickup_callback.call(slot_index, null)
					close()
		elif _modifier_mode:
			_handle_modifier_slot_click(slot_index)
		elif _remove_mode:
			_handle_remove_weapon_click(slot_index)
		else:
			if _selected_slot == -1:
				_selected_slot = slot_index
				_highlight_slot(slot_index)
			else:
				if _selected_slot != slot_index:
					_swap_weapons(_selected_slot, slot_index)
				_selected_slot = -1
				_build_cards()


func _handle_remove_weapon_click(slot_index: int) -> void:
	var weapon: Weapon = _inventory.get_weapon(slot_index)
	if weapon == null:
		_show_feedback("No weapon in that slot!")
		return
	var equipped_count := 0
	for i in range(weapon.modifier_slot_count):
		if weapon.get_modifier_at(i) != null:
			equipped_count += 1
	if equipped_count == 0:
		_show_feedback("No modifiers on that weapon!")
		return
	_remove_weapon = weapon
	_title_label.text = "Remove which modifier?"
	_build_remove_modifier_cards(weapon)


func _build_remove_modifier_cards(weapon: Weapon) -> void:
	_clear_cards()
	var cards: Array[Control] = []
	for i in range(weapon.modifier_slot_count):
		var modifier: Modifier = weapon.get_modifier_at(i)
		if modifier == null:
			continue
		var card := _create_remove_modifier_card(modifier, i)
		_cards_container.add_child(card)
		cards.append(card)
	UiAnimations.stagger_slide_in(cards, 0.1, 20.0, 0.3)


func _create_remove_modifier_card(modifier: Modifier, slot_index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var desc := modifier.get_description()
	if desc != "":
		stats.append(desc)
	stats.append("slot %d" % (slot_index + 1))
	card.populate(modifier.icon_texture, modifier.name, stats)
	card.card_clicked.connect(_on_remove_modifier_card_input.bind(slot_index))
	return card


func _on_remove_modifier_card_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _remove_weapon == null:
			return
		var weapon := _remove_weapon
		var cb := _remove_callback
		cb.call(weapon, slot_index)
		close()


func _handle_modifier_slot_click(slot_index: int) -> void:
	var weapon: Weapon = _inventory.get_weapon(slot_index)
	if weapon == null:
		_show_feedback("No weapon in that slot!")
		return
	var empty_slot := _find_empty_modifier_slot(weapon)
	if empty_slot == -1:
		_show_feedback("No empty modifier slots!")
		return
	var player_inventory := get_meta("player_inventory_ref") as PlayerInventory
	if player_inventory:
		player_inventory.remove_modifier_from_inventory(_modifier_ref)
	_inventory.add_modifier_to_weapon(slot_index, empty_slot, _modifier_ref)
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
		var c: Control = cards[slot_index]
		if c is Card:
			c.set_selected(true)
		var tween := c.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_loops()
		tween.tween_property(c, "modulate", Color(1.0, 0.85, 0.5, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(c, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _swap_weapons(slot_a: int, slot_b: int) -> void:
	if _inventory != null:
		var weapon_a = _inventory.get_weapon(slot_a)
		var weapon_b = _inventory.get_weapon(slot_b)
		_inventory.equip_weapon(slot_a, weapon_b)
		_inventory.equip_weapon(slot_b, weapon_a)


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
	for i in range(_transfer_modifiers.size()):
		var modifier: Modifier = _transfer_modifiers[i]
		var card := _create_transfer_card(modifier, i)
		_cards_container.add_child(card)
		card.modulate.a = 0.0
		cards.append(card)
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	var target_positions: Array[Vector2] = []
	for card in cards:
		target_positions.append(card.global_position)
	for card in cards:
		if is_instance_valid(card):
			_cards_container.remove_child(card)
			add_child(card)
			var placeholder := Control.new()
			placeholder.custom_minimum_size = CARD_MIN_SIZE
			_cards_container.add_child(placeholder)
			_transfer_placeholders.append(placeholder)
	for i in range(cards.size()):
		var card: Control = cards[i]
		if not is_instance_valid(card):
			continue
		var target_pos: Vector2 = target_positions[i]
		card.pivot_offset = card.size * 0.5
		if i < start_positions.size():
			var start_pos: Vector2 = start_positions[i]["position"]
			var start_sz: Vector2 = start_positions[i]["size"]
			var scale_ratio := Vector2(start_sz.x / CARD_MIN_SIZE.x, start_sz.y / CARD_MIN_SIZE.y)
			card.global_position = start_pos - (card.size - start_sz) * 0.5
			card.scale = scale_ratio
		else:
			card.global_position = target_pos
		card.modulate.a = 1.0
		if card is Card:
			var card_svp := card.get_node("SubViewportContainer/SubViewport") as SubViewport
			if card_svp:
				var cb_tween := card.create_tween()
				cb_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				cb_tween.tween_callback(func(): card_svp.render_target_update_mode = SubViewport.UPDATE_ONCE).set_delay(0.1)
		var tween := card.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_parallel(true)
		if i < start_positions.size():
			tween.tween_property(card, "global_position", target_pos, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	_transfer_card_nodes = cards


func _create_transfer_card(modifier: Modifier, index: int) -> Control:
	var card: Card = CARD_SCENE.instantiate()
	var stats: Array[String] = []
	var desc_text := modifier.get_description()
	if desc_text != "":
		stats.append(desc_text)
	card.populate(modifier.icon_texture, modifier.name, stats)
	card.modulate.a = 0.0
	card.card_clicked.connect(_on_transfer_card_input.bind(index))
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
		var skip_delay: float = 0.35 + 0.08 * max(_transfer_modifiers.size() - 1, 0) + 0.4
		UiAnimations.fade_in(_skip_button, 0.3, skip_delay)


func _on_skip_pressed() -> void:
	_pickup_callback.call(_transfer_slot, null)
	close()


func _cancel_skip_button() -> void:
	if _skip_button != null:
		_skip_button.queue_free()
		_skip_button = null
