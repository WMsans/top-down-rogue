extends Control

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_popup: Control = %SettingsPopup
@onready var button_container: VBoxContainer = %ButtonContainer

var _buttons: Array[Button] = []


func _ready() -> void:
	_apply_theme()
	_buttons = [play_button, settings_button, quit_button]
	_connect_buttons()
	_focus_first_button()


func _connect_buttons() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_popup.closed.connect(_on_settings_closed)


func _focus_first_button() -> void:
	if _buttons.size() > 0:
		_buttons[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_popup.visible:
		settings_popup.close()
		get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	SceneManager.go_to_game()


func _on_settings_pressed() -> void:
	settings_popup.open()


func _on_settings_closed() -> void:
	_focus_first_button()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "Label", 16)
	t.set_color("font_color", "Button", Color(0.976, 0.988, 0.953))
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	t.set_color("font_hover_color", "Button", Color(0.741, 0.576, 0.976))
	t.set_constant("separation", "VBoxContainer", 12)
	theme = t