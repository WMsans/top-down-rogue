extends Control

const _UiAnimations = preload("res://src/ui/ui_animations.gd")

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_popup: Control = %SettingsPopup

var _buttons: Array[Button] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	play_button.add_theme_color_override("font_color", UiTheme.ACCENT)
	_buttons = [play_button, settings_button, quit_button]
	for btn in _buttons:
		UiAnimations.setup_button_hover(btn)
	_connect_buttons()
	_play_entrance()


func _connect_buttons() -> void:
	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_popup.closed.connect(_on_settings_closed)


func _play_entrance() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and settings_popup.visible:
		settings_popup.close()
		get_viewport().set_input_as_handled()


func _on_play_pressed() -> void:
	SceneManager.go_to_game()


func _on_settings_pressed() -> void:
	settings_popup.open()


func _on_settings_closed() -> void:
	play_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()
