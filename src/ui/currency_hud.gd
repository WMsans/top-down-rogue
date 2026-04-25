class_name CurrencyHUD
extends CanvasLayer

const COIN_TEXTURE := preload("res://textures/Assets/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/16x16/coin_01a.png")

var _gold_label: Label
var _coin_icon: TextureRect


func _ready() -> void:
	var container := HBoxContainer.new()
	container.position = Vector2(get_viewport().get_visible_rect().size.x - 120, 8)
	container.theme = UiTheme.get_theme()
	add_child(container)

	_coin_icon = TextureRect.new()
	_coin_icon.texture = COIN_TEXTURE
	_coin_icon.custom_minimum_size = Vector2(16, 16)
	_coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(_coin_icon)

	_gold_label = Label.new()
	_gold_label.text = "0"
	_gold_label.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_gold_label.add_theme_font_size_override("font_size", 16)
	container.add_child(_gold_label)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var wallet := player.get_node_or_null("WalletComponent")
		if wallet:
			wallet.gold_changed.connect(_on_gold_changed)
			_on_gold_changed(wallet.gold)


func _on_gold_changed(amount: int) -> void:
	_gold_label.text = str(amount)
