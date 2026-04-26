# src/economy/shop_ui.gd
class_name ShopUI
extends CanvasLayer

const CARD_MIN_SIZE := Vector2(160, 200)
const MODIFIER_ICON_SIZE := Vector2(48, 48)
const CARD_GLOW_SHADER := preload("res://shaders/ui/card_hover_glow.gdshader")

var _remove_cost: int = 50
var _remove_count: int = 0
var _offerings: Array[ShopOffer] = []

@onready var _overlay: ColorRect = %Overlay
@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _buy_container: HBoxContainer = %BuyContainer
@onready var _remove_button: Button = %RemoveButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var theme := UiTheme.get_theme()
	_title_label.theme = theme
	_gold_label.theme = theme
	_overlay.gui_input.connect(_on_overlay_input)
	_close_button.pressed.connect(close)
	_remove_button.pressed.connect(_on_remove_pressed)
	visible = false


func open(offerings: Array[ShopOffer]) -> void:
	_offerings = offerings
	_remove_count = 0
	_refresh_gold()
	_build_buy_grid()
	_build_remove_section()
	SceneManager.set_paused(true)
	visible = true


func close() -> void:
	_clear_buy_grid()
	visible = false
	SceneManager.set_paused(false)


func _refresh_gold() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			_gold_label.text = "Gold: %d" % wallet.gold


func _build_buy_grid() -> void:
	_clear_buy_grid()
	for offer in _offerings:
		var card := _create_offer_card(offer)
		_buy_container.add_child(card)


func _clear_buy_grid() -> void:
	for child in _buy_container.get_children():
		child.queue_free()


func _create_offer_card(offer: ShopOffer) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_MIN_SIZE
	card.theme = UiTheme.get_theme()

	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = CARD_GLOW_SHADER
	glow_mat.set_shader_parameter("glow_enabled", false)
	card.material = glow_mat

	card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	if offer.modifier.icon_texture:
		var icon := TextureRect.new()
		icon.texture = offer.modifier.icon_texture
		icon.custom_minimum_size = MODIFIER_ICON_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)

	var name_label := Label.new()
	name_label.text = offer.modifier.name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	vbox.add_child(name_label)

	var desc := offer.modifier.get_description()
	if desc != "":
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size.x = CARD_MIN_SIZE.x - 16
		desc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		desc_label.add_theme_font_size_override("font_size", 13)
		vbox.add_child(desc_label)

	var price_label := Label.new()
	price_label.text = "%d gold" % offer.price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	vbox.add_child(price_label)

	var buy_button := Button.new()
	buy_button.text = "Buy"
	buy_button.theme = UiTheme.get_theme()
	buy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy_button.pressed.connect(_on_buy_pressed.bind(offer, card))
	vbox.add_child(buy_button)

	return card


func _on_buy_pressed(offer: ShopOffer, card: Control) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var wallet := player.get_node_or_null("WalletComponent")
	var inventory := player.get_node_or_null("ModifierInventory")
	if not wallet or not inventory:
		return
	if not wallet.spend_gold(offer.price):
		return
	# Move modifier from shop offer to player inventory
	var mod: Modifier = offer.modifier
	_offerings.erase(offer)
	card.queue_free()
	inventory.add_modifier(mod)
	_refresh_gold()


func _build_remove_section() -> void:
	_remove_cost = 50 + _remove_count * 25
	_remove_button.text = "Remove Modifier (%d gold)" % _remove_cost

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var inventory := player.get_node_or_null("ModifierInventory")
		var wallet := player.get_node_or_null("WalletComponent")
		var can_afford: bool = wallet != null and wallet.gold >= _remove_cost
		var has_mods: bool = inventory != null and inventory.has_modifiers()
		_remove_button.disabled = not (can_afford and has_mods)


func _on_remove_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var inventory := player.get_node_or_null("ModifierInventory")
	var wallet := player.get_node_or_null("WalletComponent")
	if not inventory or not wallet:
		return
	var mods: Array[Modifier] = inventory.get_modifiers()
	if mods.size() == 0:
		return
	if not wallet.spend_gold(_remove_cost):
		return
	inventory.remove_modifier(mods[-1])
	_remove_count += 1
	_refresh_gold()
	_build_remove_section()


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
