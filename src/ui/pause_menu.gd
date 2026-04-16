extends CanvasLayer

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

@onready var pause_panel: Control = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var main_menu_button: Button = %MainMenuButton
@onready var settings_popup: Control = %SettingsPopup
@onready var confirmation_panel: Control = %ConfirmationPanel
@onready var confirm_yes_button: Button = %ConfirmYesButton
@onready var confirm_no_button: Button = %ConfirmNoButton

var _buttons: Array[Button] = []


func _ready() -> void:
	_apply_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons = [resume_button, settings_button, main_menu_button]
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


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Button", Color(0.976, 0.988, 0.953))
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	t.set_color("font_hover_color", "Button", Color(0.741, 0.576, 0.976))
	t.set_constant("separation", "VBoxContainer", 12)
	pause_panel.theme = t
