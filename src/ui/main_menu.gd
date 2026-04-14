extends Control

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_popup: Control = %SettingsPopup
@onready var button_container: VBoxContainer = %ButtonContainer

var _buttons: Array[Button] = []


func _ready() -> void:
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