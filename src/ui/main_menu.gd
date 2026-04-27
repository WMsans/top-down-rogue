extends Control

const _UiTheme = preload("res://src/ui/ui_theme.gd")
const _UiAnimations = preload("res://src/ui/ui_animations.gd")

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_popup: Control = %SettingsPopup
@onready var button_container: VBoxContainer = %ButtonContainer
@onready var title_top: Label = %TitleTop
@onready var title_bottom: Label = %TitleBottom
@onready var menu_card: PanelContainer = %MenuCard

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
	title_top.modulate.a = 0.0
	title_bottom.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(title_top, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_LINEAR)
	tween.parallel().tween_property(title_bottom, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_LINEAR).set_delay(0.1)
	UiAnimations.slide_in_up(button_container, 20.0, 0.4)


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