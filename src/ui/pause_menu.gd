extends CanvasLayer

@onready var pause_panel: Control = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var settings_popup: Control = %SettingsPopup
@onready var confirmation_panel: Control = %ConfirmationPanel
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_no_button: Button = %ConfirmNoButton
@onready var pause_card: PanelContainer = %PauseCard
@onready var dimmer: ColorRect = %Dimmer

var _buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	main_menu_button.add_theme_color_override("font_color", UiTheme.DANGER)
	main_menu_button.add_theme_color_override("font_hover_color", UiTheme.DANGER)
	confirm_yes_button.add_theme_color_override("font_color", UiTheme.DANGER)
	confirm_yes_button.add_theme_color_override("font_hover_color", UiTheme.DANGER)
	confirm_no_button.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	confirm_no_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_GOLD)
	_buttons = [resume_button, settings_button, main_menu_button]
	for btn in _buttons:
		UiAnimations.setup_button_hover(btn)
	UiAnimations.setup_button_hover(confirm_yes_button)
	UiAnimations.setup_button_hover(confirm_no_button)
	_connect_buttons()
	confirmation_panel.visible = false
	pause_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var weapon_popup := get_tree().root.find_child("WeaponPopup", true, false)
	if weapon_popup != null and weapon_popup.visible:
		return
	if event.is_action_pressed("pause"):
		if settings_popup.visible:
			settings_popup.close()
		elif confirmation_panel.visible:
			confirmation_panel.visible = false
			_focus_first_button()
		elif pause_panel.visible:
			_resume_game()
		else:
			_show_pause()
		get_viewport().set_input_as_handled()


func _connect_buttons() -> void:
	resume_button.pressed.connect(_resume_game)
	settings_button.pressed.connect(_on_settings_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	settings_popup.closed.connect(_on_settings_closed)
	confirm_yes_button.pressed.connect(_on_confirm_yes)
	confirm_no_button.pressed.connect(_on_confirm_no)


func _show_pause() -> void:
	SceneManager.set_paused(true)
	pause_panel.visible = true
	confirmation_panel.visible = false
	dimmer.color.a = 0.0
	pause_card.position.y += 30.0
	pause_card.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(dimmer, "color:a", 0.7, 0.25).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(pause_card, "position:y", pause_card.position.y - 30.0, 0.3).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pause_card, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_LINEAR)
	_focus_first_button()


func _resume_game() -> void:
	pause_panel.visible = false
	SceneManager.set_paused(false)


func _on_settings_pressed() -> void:
	settings_popup.open()


func _on_settings_closed() -> void:
	_focus_first_button()


func _on_main_menu_pressed() -> void:
	confirmation_panel.visible = true
	confirm_no_button.grab_focus()


func _on_confirm_yes() -> void:
	SceneManager.set_paused(false)
	pause_panel.visible = false
	SceneManager.go_to_main_menu()


func _on_confirm_no() -> void:
	confirmation_panel.visible = false
	_focus_first_button()


func _focus_first_button() -> void:
	if _buttons.size() > 0:
		_buttons[0].grab_focus()