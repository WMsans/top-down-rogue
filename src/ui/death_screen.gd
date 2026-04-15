extends CanvasLayer

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

@onready var _overlay: ColorRect = %Overlay
@onready var _red_flash: ColorRect = %RedFlash
@onready var _died_label: Label = %DiedLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _vbox: VBoxContainer = %DeathVBox

var _health_component: HealthComponent


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.visible = false
	_red_flash.visible = false
	_vbox.visible = false
	_apply_theme()
	_continue_button.pressed.connect(_on_continue_pressed)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		_health_component = player.get_node("HealthComponent")
		_health_component.died.connect(_on_player_died)


func _on_player_died() -> void:
	SceneManager.set_paused(true)
	_play_death_sequence()


func _play_death_sequence() -> void:
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.visible = true
	_red_flash.color = Color(1, 0, 0, 0)
	_red_flash.visible = true
	_vbox.visible = true
	_died_label.modulate.a = 0.0
	_continue_button.modulate.a = 0.0
	_continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

	tween.parallel().tween_property(_red_flash, "color:a", 0.4, 0.15).from(0.0)
	tween.parallel().tween_property(_overlay, "color:a", 0.7, 0.8).from(0.0)
	tween.parallel().tween_property(_red_flash, "color:a", 0.0, 0.15).from(0.4).set_delay(0.15)
	tween.chain().tween_interval(0.5)
	tween.tween_property(_died_label, "modulate:a", 1.0, 0.5).from(0.0)
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
	t.set_font_size("font_size", "Label", 32)
	t.set_color("font_color", "Button", Color(0.976, 0.988, 0.953))
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	t.set_color("font_hover_color", "Button", Color(0.741, 0.576, 0.976))
	_vbox.theme = t
