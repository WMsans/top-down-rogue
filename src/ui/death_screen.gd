extends CanvasLayer

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox
@onready var _vignette: ColorRect = %VignetteOverlay

var _health_component: HealthComponent


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_vbox.theme = UiTheme.get_theme()
	_died_label.add_theme_font_size_override("font_size", 64)
	_died_label.add_theme_color_override("font_color", UiTheme.DANGER)
	_died_label.add_theme_constant_override("outline_size", 4)
	_died_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_continue_button.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	_continue_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_GOLD)
	UiAnimations.setup_button_hover(_continue_button, 1.05, 0.95)
	_continue_button.pressed.connect(_on_continue_pressed)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	visible = true
	SceneManager.set_paused(true)
	_play_death_sequence()


func _play_death_sequence() -> void:
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = true
	_red_flash.color = Color(0.6, 0, 0, 0)
	_red_flash.visible = true
	_vignette.color = Color(0, 0, 0, 0)
	_vignette.visible = true
	_died_label.modulate.a = 0.0
	_died_label.scale = Vector2(0.6, 0.6)
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# Red flash: 0 → 0.6 in 0.08s, then 0.6 → 0 in 0.5s
	tween.tween_property(_red_flash, "color:a", 0.6, 0.08).from(0.0)
	tween.tween_property(_red_flash, "color:a", 0.0, 0.5)

	# Screen shake on the VBox
	tween.parallel().tween_property(_vbox, "position:x", 4.0, 0.075).from(0.0).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -4.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 3.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", -2.0, 0.075).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(_vbox, "position:x", 0.0, 0.075).set_trans(Tween.TRANS_SINE)

	# Dark overlay: 0 → 0.8 over 0.8s
	tween.parallel().tween_property(_overlay, "color:a", 0.8, 0.8).from(0.0).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)

	# Vignette fades in
	tween.parallel().tween_property(_vignette, "color:a", 1.0, 0.8).from(0.0)

	# "YOU DIED" scale 0.6 → 1.0 over 0.5s with back ease-out
	tween.tween_property(_died_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_died_label, "modulate:a", 1.0, 0.3)

	# Continue button fades in after 0.7s delay
	tween.tween_interval(0.7)
	tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(_on_sequence_complete)


func _on_sequence_complete() -> void:
	_continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	SceneManager.set_paused(false)
	SceneManager.go_to_main_menu()
