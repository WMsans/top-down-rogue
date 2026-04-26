# src/economy/shop_ui.gd
class_name ShopUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(140, 210)
const MODIFIER_ICON_SIZE := Vector2(48, 48)
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

signal reroll_requested

var _remove_cost: int = 50
var _remove_count: int = 0
var _displayed_gold: int = 0
var _offerings: Array[ShopOffer] = []
var _price_labels: Array[Label] = []
var _card_slots: Array[Control] = []
var _remove_card: PanelContainer = null
var _remove_price_label: Label = null

@onready var _shop_panel: PanelContainer = %ShopPanel
@onready var _header_bar: PanelContainer = %HeaderBar
@onready var _action_bar: PanelContainer = %ActionBar
@onready var _reroll_button: Button = %RerollButton
@onready var _overlay: ColorRect = %Overlay
@onready var _gold_label: Label = %GoldLabel
@onready var _buy_container: HBoxContainer = %BuyContainer
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.gui_input.connect(_on_overlay_input)
	_close_button.pressed.connect(close)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	UiAnimations.setup_button_hover(_reroll_button)
	UiAnimations.setup_button_hover(_close_button)
	_apply_bar_styles()
	_style_action_buttons()
	_style_header_labels()
	visible = false


func _apply_bar_styles() -> void:
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


func _style_action_buttons() -> void:
	var theme := UiTheme.get_theme()
	_reroll_button.theme = theme
	_close_button.theme = theme
	_reroll_button.add_theme_font_size_override("font_size", 16)
	_close_button.add_theme_font_size_override("font_size", 16)
	_reroll_button.custom_minimum_size = Vector2(0, 36)
	_close_button.custom_minimum_size = Vector2(0, 36)


func _style_header_labels() -> void:
	var hbox := _header_bar.get_node_or_null("HeaderHBox")
	if not hbox:
		return
	var title := hbox.get_node_or_null("TitleLabel") as Label
	if title:
		title.add_theme_font_override("font", UiTheme.PIXEL_FONT)
		title.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		title.add_theme_font_size_override("font_size", 28)
	_gold_label.add_theme_font_override("font", UiTheme.PIXEL_FONT)
	_gold_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_gold_label.add_theme_font_size_override("font_size", 22)


func open(offerings: Array[ShopOffer]) -> void:
	_offerings = offerings
	_remove_count = 0
	var gold := _get_player_gold()
	_displayed_gold = gold
	_gold_label.text = "gold: %d" % gold
	_build_buy_grid()
	SceneManager.set_paused(true)
	visible = true
	_play_entrance_animation()


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
	for child in _buy_container.get_children():
		var slot := child as Control
		if slot:
			slot.position.y += 20
			slot.modulate.a = 0.0
			cards.append(slot)
	for i in cards.size():
		var tween := cards[i].create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(0.08 * i)
		tween.parallel().tween_property(cards[i], "position:y", cards[i].position.y - 20, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(cards[i], "modulate:a", 1.0, 0.3)


func close() -> void:
	_clear_buy_grid()
	visible = false
	SceneManager.set_paused(false)


func _refresh_gold() -> void:
	var gold := _get_player_gold()
	if gold == _displayed_gold:
		_refresh_price_colors(gold)
		_refresh_remove_affordability(gold)
		return
	var old_gold := _displayed_gold
	var gold_tween := create_tween()
	gold_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	gold_tween.tween_method(_set_displayed_gold, old_gold, gold, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animate_gold_bounce()
	_refresh_price_colors(gold)
	_refresh_remove_affordability(gold)


func _set_displayed_gold(value: int) -> void:
	_displayed_gold = roundi(value)
	_gold_label.text = "gold: %d" % _displayed_gold


func _animate_gold_bounce() -> void:
	var tween := _gold_label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_gold_label, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_gold_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _refresh_price_colors(gold: int) -> void:
	for i in _price_labels.size():
		if i >= _offerings.size():
			continue
		if _offerings[i] != null:
			if gold >= _offerings[i].price:
				_price_labels[i].add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
			else:
				_price_labels[i].add_theme_color_override("font_color", UiTheme.DANGER)


func _refresh_remove_affordability(gold: int) -> void:
	if _remove_price_label:
		if gold >= _remove_cost:
			_remove_price_label.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		else:
			_remove_price_label.add_theme_color_override("font_color", UiTheme.DANGER)


func _build_buy_grid() -> void:
	_clear_buy_grid()
	_price_labels.clear()
	_card_slots.clear()
	_remove_card = null
	_remove_price_label = null

	var gold := _get_player_gold()
	for offer in _offerings:
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_theme_constant_override("separation", 4)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

		var card := _create_offer_card(offer, slot)
		slot.add_child(card)
		_card_slots.append(slot)

		var price_label := Label.new()
		price_label.text = "%d gold" % offer.price
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_font_size_override("font_size", 20)
		if gold >= offer.price:
			price_label.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		else:
			price_label.add_theme_color_override("font_color", UiTheme.DANGER)
		slot.add_child(price_label)
		_price_labels.append(price_label)

		_buy_container.add_child(slot)

	_remove_cost = 50 + _remove_count * 25
	var remove_slot := VBoxContainer.new()
	remove_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	remove_slot.add_theme_constant_override("separation", 4)
	remove_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var remove_card := _create_remove_card()
	remove_slot.add_child(remove_card)
	_remove_card = remove_card

	var remove_label := Label.new()
	remove_label.text = "%d gold" % _remove_cost
	remove_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remove_label.add_theme_font_size_override("font_size", 20)
	if gold >= _remove_cost:
		remove_label.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	else:
		remove_label.add_theme_color_override("font_color", UiTheme.DANGER)
	remove_slot.add_child(remove_label)
	_remove_price_label = remove_label

	_buy_container.add_child(remove_slot)


func _clear_buy_grid() -> void:
	for child in _buy_container.get_children():
		child.queue_free()
	_price_labels.clear()
	_card_slots.clear()
	_remove_card = null
	_remove_price_label = null


func _create_offer_card(offer: ShopOffer, slot: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
	card.gui_input.connect(_on_card_gui_input.bind(offer, card, slot))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = MODIFIER_ICON_SIZE * 1.6
	vbox.add_child(icon_container)

	if offer.modifier.icon_texture:
		var icon := TextureRect.new()
		icon.texture = offer.modifier.icon_texture
		icon.custom_minimum_size = MODIFIER_ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_container.add_child(icon)

	var name_label := Label.new()
	name_label.text = offer.modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var desc := offer.modifier.get_description()
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc_label)

	return card


func _create_remove_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
	card.gui_input.connect(_on_remove_card_input.bind(card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = MODIFIER_ICON_SIZE * 1.6
	vbox.add_child(icon_container)

	var x_label := Label.new()
	x_label.text = "x"
	x_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x_label.add_theme_color_override("font_color", UiTheme.DANGER)
	x_label.add_theme_font_size_override("font_size", 48)
	icon_container.add_child(x_label)

	var name_label := Label.new()
	name_label.text = "Remove Modifier"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.DANGER)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = "Removes the last modifier from your inventory"
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
	desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	desc_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc_label)

	return card


func _on_buy_pressed(offer: ShopOffer, card: Control, slot: Control) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var wallet: WalletComponent = player.get_node_or_null("WalletComponent")
	var weapon_manager: WeaponManager = player.get_node_or_null("WeaponManager")
	if not wallet or not weapon_manager:
		return

	if wallet.gold < offer.price:
		UiAnimations.jitter_bounce(card)
		_shake_gold_label()
		var idx_fail := _card_slots.find(slot)
		if idx_fail >= 0 and idx_fail < _price_labels.size():
			_pulse_price_label(_price_labels[idx_fail])
		return

	if not _has_weapon_with_empty_slot(weapon_manager):
		UiAnimations.jitter_bounce(card)
		return

	var popup := player.get_parent().get_node_or_null("WeaponPopup")
	if not popup:
		return

	var equipped := [false]
	var on_equip := func() -> void:
		equipped[0] = true

	visible = false
	popup.open_for_modifier(weapon_manager, offer.modifier, on_equip)
	await popup.visibility_changed
	visible = true
	SceneManager.set_paused(true)

	if not equipped[0]:
		return

	wallet.spend_gold(offer.price)

	var idx := _card_slots.find(slot)
	if idx >= 0:
		_offerings[idx] = null
		if idx < _price_labels.size():
			_price_labels[idx].text = "SOLD"
			_price_labels[idx].add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in card.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if card.material is ShaderMaterial:
			card.material.set_shader_parameter("glow_enabled", false)
		var dim_tween := card.create_tween()
		dim_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		dim_tween.tween_property(card, "modulate:a", 0.4, 0.2)

	_refresh_gold()


func _has_weapon_with_empty_slot(weapon_manager: WeaponManager) -> bool:
	for weapon in weapon_manager.weapons:
		if weapon != null and weapon.find_empty_modifier_slot() != -1:
			return true
	return false


func _has_any_equipped_modifier(weapon_manager: WeaponManager) -> bool:
	for weapon in weapon_manager.weapons:
		if weapon == null:
			continue
		for m_idx in range(weapon.modifier_slot_count):
			if weapon.get_modifier_at(m_idx) != null:
				return true
	return false



func _on_remove_pressed(card: PanelContainer) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var wallet: WalletComponent = player.get_node_or_null("WalletComponent")
	var weapon_manager: WeaponManager = player.get_node_or_null("WeaponManager")
	if not wallet or not weapon_manager:
		return
	if not _has_any_equipped_modifier(weapon_manager):
		UiAnimations.jitter_bounce(card)
		return
	if wallet.gold < _remove_cost:
		UiAnimations.jitter_bounce(card)
		_shake_gold_label()
		if _remove_price_label:
			_pulse_price_label(_remove_price_label)
		return

	var popup := get_tree().get_first_node_in_group("player").get_parent().get_node_or_null("WeaponPopup")
	if not popup:
		return

	var picked: Array = []
	var on_pick := func(weapon: Weapon, slot_idx: int) -> void:
		picked = [weapon, slot_idx]

	visible = false
	popup.open_for_remove(weapon_manager, on_pick)
	await popup.visibility_changed
	visible = true
	SceneManager.set_paused(true)

	if picked.is_empty():
		return
	if not wallet.spend_gold(_remove_cost):
		return
	var weapon: Weapon = picked[0]
	var slot_idx: int = picked[1]
	weapon.modifiers[slot_idx] = null
	_remove_count += 1
	_remove_cost = 50 + _remove_count * 25
	if _remove_price_label:
		_remove_price_label.text = "%d gold" % _remove_cost
	_refresh_gold()


func _shake_gold_label() -> void:
	var base_pos := _gold_label.position
	var tween := _gold_label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_gold_label.add_theme_color_override("font_color", UiTheme.DANGER)
	for offset in [6.0, -5.0, 4.0, -3.0, 0.0]:
		tween.tween_property(_gold_label, "position:x", base_pos.x + offset, 0.05).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		_gold_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	)


func _pulse_price_label(label: Label) -> void:
	var tween := label.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(label, "scale", Vector2(1.15, 1.15), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_reroll_pressed() -> void:
	reroll_requested.emit()


func _get_player_gold() -> int:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			return wallet.gold
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


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
	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style := style.duplicate() as StyleBoxFlat
		new_style.border_color = UiTheme.PANEL_BORDER
		card.add_theme_stylebox_override("panel", new_style)


func _on_card_gui_input(event: InputEvent, offer: ShopOffer, card: PanelContainer, slot: Control) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_buy_pressed(offer, card, slot)


func _on_remove_card_input(event: InputEvent, card: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_remove_pressed(card)
