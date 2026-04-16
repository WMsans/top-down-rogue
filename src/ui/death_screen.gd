extends CanvasLayer

const PIXEL_FONT := preload("res://textures/Assets/DawnLike/GUI/SDS_8x8.ttf")

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox

var _health_component: HealthComponent


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_theme()
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
	_vbox.visible = true
	_died_label.modulate.a = 0.0
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	# Quick red flash
	tween.tween_property(_red_flash, "color:a", 0.5, 0.1).from(0.0)
	tween.tween_property(_red_flash, "color:a", 0.0, 0.4)
	# Dark overlay fades in
	tween.parallel().tween_property(_overlay, "color:a", 0.75, 1.0).from(0.0)
	# Pause before text
	tween.tween_interval(0.3)
	# "YOU DIED" fades in
	tween.tween_property(_died_label, "modulate:a", 1.0, 0.6).from(0.0)
	tween.tween_interval(0.4)
	# Button fades in
	tween.tween_property(_continue_button, "modulate:a", 1.0, 0.3).from(0.0)
	tween.tween_callback(_on_sequence_complete)


func _on_sequence_complete() -> void:
	_continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	SceneManager.set_paused(false)
	SceneManager.go_to_main_menu()


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Button", 24)
	t.set_font_size("font_size", "Label", 48)
	t.set_color("font_color", "Button", Color(0.8, 0.8, 0.8))
	t.set_color("font_color", "Label", Color(0.85, 0.15, 0.15))
	t.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	_vbox.theme = t
