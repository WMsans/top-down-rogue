extends CanvasLayer

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _flavor_label: Label = %FlavorLabel
@onready var _stats_label: RichTextLabel = %StatsLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox
@onready var _panel: PanelContainer = %DeathPanel
@onready var _vignette: ColorRect = %VignetteOverlay

var _inventory: PlayerInventory


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_vbox.theme = UiTheme.get_theme()
	_panel.theme = UiTheme.get_theme()

	_died_label.add_theme_font_size_override("font_size", 72)
	_died_label.add_theme_color_override("font_color", UiTheme.DANGER)
	_died_label.add_theme_constant_override("outline_size", 6)
	_died_label.add_theme_color_override("font_outline_color", Color.BLACK)

	_flavor_label.add_theme_font_size_override("font_size", 18)
	_flavor_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)

	_continue_button.add_theme_font_size_override("font_size", 22)
	_continue_button.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_continue_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT)
	_continue_button.add_theme_color_override("font_focus_color", UiTheme.ACCENT_GOLD)
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = UiTheme.SURFACE_BG
	focus_style.border_color = UiTheme.DANGER
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(6)
	focus_style.set_content_margin_all(6)
	focus_style.content_margin_left = 10
	focus_style.content_margin_right = 10
	_continue_button.add_theme_stylebox_override("focus", focus_style)
	UiAnimations.setup_button_hover(_continue_button, 1.05, 0.95)
	_continue_button.pressed.connect(_on_continue_pressed)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		var inventory: PlayerInventory = player.get_node_or_null("PlayerInventory")
		if inventory:
			_inventory = inventory
			inventory.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	visible = true
	_populate_stats()
	SceneManager.set_paused(true)
	_play_death_sequence()


func _populate_stats() -> void:
	var max_hp := _inventory.get_max_health() if _inventory else 0
	var secondary := UiTheme.TEXT_SECONDARY.to_html(false)
	var primary := UiTheme.TEXT_PRIMARY.to_html(false)
	_stats_label.text = "[center][color=#%s]Max HP:[/color] [color=#%s]%d[/color][/center]" % [
		secondary, primary, max_hp
	]


func _play_death_sequence() -> void:
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = true
	_red_flash.color = Color(0.6, 0, 0, 0)
	_red_flash.visible = true
	_vignette.color = Color(0, 0, 0, 0)
	_vignette.visible = true

	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.6, 0.6)
	_panel.pivot_offset = _panel.size * 0.5

	_died_label.modulate.a = 0.0
	_flavor_label.modulate.a = 0.0
	_stats_label.modulate.a = 0.0
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	tween.tween_property(_red_flash, "color:a", 0.6, 0.08).from(0.0)
	tween.tween_property(_red_flash, "color:a", 0.0, 0.5)

	tween.parallel().tween_property(_vbox, "position:x", 4.0, 0.075).from(0.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -4.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 3.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -2.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 0.0, 0.075).set_trans(Tween.TRANS_SINE)

	tween.parallel().tween_property(_overlay, "color:a", 0.85, 0.8).from(0.0).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_vignette, "color:a", 1.0, 0.8).from(0.0)

	tween.tween_callback(func(): _panel.pivot_offset = _panel.size * 0.5)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.tween_property(_died_label, "modulate:a", 1.0, 0.25)
	tween.tween_property(_flavor_label, "modulate:a", 1.0, 0.25)
	tween.tween_property(_stats_label, "modulate:a", 1.0, 0.25)
	tween.tween_interval(0.2)
	tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3)
	tween.tween_callback(_on_sequence_complete)


func _on_sequence_complete() -> void:
	_continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	SceneManager.set_paused(false)
	SceneManager.go_to_main_menu()
