extends Control

signal closed

const PIXEL_FONT := preload("res://textures/DawnLike/GUI/SDS_8x8.ttf")

const SETTINGS_PATH := "user://settings.cfg"

const SECTION_AUDIO := "audio"
const SECTION_DISPLAY := "display"
const SECTION_KEYS := "keys"

var _rebinding_action := ""
var _rebinding_label: Label = null

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_button: Button = %FullscreenButton
@onready var close_button: Button = %CloseButton
@onready var back_button: Button = %BackButton
@onready var key_bindings_container: VBoxContainer = %KeyBindingsContainer


func _ready() -> void:
	_apply_theme()
	_connect_signals()
	_apply_loaded_settings()


func _connect_signals() -> void:
	master_slider.value_changed.connect(_on_volume_changed.bind("Master"))
	music_slider.value_changed.connect(_on_volume_changed.bind("Music"))
	sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX"))
	fullscreen_button.pressed.connect(_on_fullscreen_toggled)
	close_button.pressed.connect(close)
	back_button.pressed.connect(close)


func open() -> void:
	_apply_loaded_settings()
	visible = true
	back_button.grab_focus()


func close() -> void:
	_save_settings()
	_rebinding_action = ""
	_rebinding_label = null
	visible = false
	closed.emit()


func _apply_loaded_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		master_slider.value = 80
		music_slider.value = 60
		sfx_slider.value = 80
		_update_fullscreen_text()
		_rebuild_key_bindings()
		return

	master_slider.value = config.get_value(SECTION_AUDIO, "master", 80)
	music_slider.value = config.get_value(SECTION_AUDIO, "music", 60)
	sfx_slider.value = config.get_value(SECTION_AUDIO, "sfx", 80)
	_update_fullscreen_text()
	_rebuild_key_bindings()


func _on_volume_changed(value: float, bus_name: String) -> void:
	var db_value := linear_to_db(value / 100.0)
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db_value)


func _on_fullscreen_toggled() -> void:
	if DisplayServer.get_window_flag(DisplayServer.WINDOW_FLAG_FULLSCREEN):
		DisplayServer.set_window_flag(DisplayServer.WINDOW_FLAG_FULLSCREEN, false)
	else:
		DisplayServer.set_window_flag(DisplayServer.WINDOW_FLAG_FULLSCREEN, true)
	_update_fullscreen_text()


func _update_fullscreen_text() -> void:
	if DisplayServer.get_window_flag(DisplayServer.WINDOW_FLAG_FULLSCREEN):
		fullscreen_button.text = "ON"
	else:
		fullscreen_button.text = "OFF"


func _on_key_binding_pressed(action: String, label: Label) -> void:
	_rebinding_action = action
	_rebinding_label = label
	_rebinding_label.text = "..."
	_clear_action_events(action)
	_rebuild_key_bindings()


func _clear_action_events(action: String) -> void:
	InputMap.action_erase_events(action)


func _input(event: InputEvent) -> void:
	if _rebinding_action == "":
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_rebinding_action = ""
			_rebinding_label = null
			_rebuild_key_bindings()
			get_viewport().set_input_as_handled()
			return

		InputMap.action_add_event(_rebinding_action, event)
		_rebinding_action = ""
		_rebinding_label = null
		_rebuild_key_bindings()
		get_viewport().set_input_as_handled()


func _rebuild_key_bindings() -> void:
	for child in key_bindings_container.get_children():
		child.queue_free()

	var actions := ["move_up", "move_down", "move_left", "move_right"]
	var labels := ["Move Up", "Move Down", "Move Left", "Move Right"]

	for i in actions.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)

		var name_label := Label.new()
		name_label.text = labels[i]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var key_button := Button.new()
		var events := InputMap.action_get_events(actions[i])
		if events.size() > 0:
			var ev: InputEvent = events[0]
			if ev is InputEventKey:
				key_button.text = OS.get_keycode_string(ev.keycode)
			else:
				key_button.text = "???"
		else:
			key_button.text = "???"

		var action := actions[i]
		key_button.pressed.connect(_on_key_binding_pressed.bind(action, key_button))
		row.add_child(key_button)

		key_bindings_container.add_child(row)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "master", master_slider.value)
	config.set_value(SECTION_AUDIO, "music", music_slider.value)
	config.set_value(SECTION_AUDIO, "sfx", sfx_slider.value)
	config.save(SETTINGS_PATH)


func _apply_theme() -> void:
	var t := Theme.new()
	t.default_font = PIXEL_FONT
	t.set_font_size("font_size", "Button", 16)
	t.set_font_size("font_size", "Label", 16)
	t.set_font_size("font_size", "HSlider", 12)
	t.set_color("font_color", "Button", Color(0.976, 0.988, 0.953))
	t.set_color("font_color", "Label", Color(0.976, 0.988, 0.953))
	t.set_color("font_hover_color", "Button", Color(0.741, 0.576, 0.976))
	t.set_constant("separation", "VBoxContainer", 8)
	theme = t