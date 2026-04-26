extends CanvasLayer

const OUTPUT_FONT_SIZE := 14
const INPUT_FONT_SIZE := 14
const MAX_HISTORY := 50
const MAX_OUTPUT_LINES := 200

var _registry: CommandRegistry
var _history: Array[String] = []
var _history_index: int = -1
var _console_visible: bool = false

var _panel: PanelContainer
var _output: RichTextLabel
var _suggestions: VBoxContainer
var _input: LineEdit


func _ready() -> void:
	_registry = CommandRegistry.new()
	_register_commands()
	_build_ui()
	process_mode = PROCESS_MODE_ALWAYS
	hide()


func _register_commands() -> void:
	var SpawnCommands := preload("res://src/console/commands/spawn_command.gd")
	SpawnCommands.register(_registry)
	var SpawnMatCommands := preload("res://src/console/commands/spawn_mat_command.gd")
	SpawnMatCommands.register(_registry)
	var ShopCommands := preload("res://src/console/commands/shop_command.gd")
	ShopCommands.register(_registry)


func _build_ui() -> void:
	layer = 128

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 4.0
	_panel.offset_right = -4.0
	_panel.offset_top = -200.0
	_panel.offset_bottom = -4.0
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_output = RichTextLabel.new()
	_output.add_theme_font_size_override("normal_font_size", OUTPUT_FONT_SIZE)
	_output.add_theme_color_override("default_color", Color.WHITE)
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.selection_enabled = true
	_output.context_menu_enabled = false
	_output.fit_content = true
	scroll.add_child(_output)

	_suggestions = VBoxContainer.new()
	vbox.add_child(_suggestions)
	_suggestions.hide()

	_input = LineEdit.new()
	_input.add_theme_font_size_override("font_size", INPUT_FONT_SIZE)
	_input.add_theme_color_override("font_color", Color.WHITE)
	_input.placeholder_text = "Type command... (Tab to autocomplete)"
	_input.add_theme_color_override("placeholder_color", Color(0.5, 0.5, 0.5))
	_input.text_submitted.connect(_on_input_submitted)
	_input.text_changed.connect(_on_text_changed)
	vbox.add_child(_input)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_QUOTELEFT:
			_toggle()
		elif _console_visible:
			match event.keycode:
				KEY_ESCAPE:
					_close()
				KEY_UP:
					_cycle_history(-1)
				KEY_DOWN:
					_cycle_history(1)
				KEY_TAB:
					_autocomplete()
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	if _console_visible:
		_close()
	else:
		_open()


func _open() -> void:
	_console_visible = true
	show()
	_input.clear()
	_input.grab_focus()
	_history_index = _history.size()
	_suggestions.hide()


func _close() -> void:
	_console_visible = false
	hide()
	_input.release_focus()
	_suggestions.hide()


func _on_input_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		_input.clear()
		return
	_execute(trimmed)
	_history.append(trimmed)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_history_index = _history.size()
	_input.clear()


func _execute(input: String) -> void:
	_append_output("> " + input, Color.GRAY)
	var result := _registry.parse(input)

	if result.error != "":
		var is_incomplete := result.error.begins_with("incomplete:")
		var color := Color(1.0, 0.7, 0.3) if is_incomplete else Color.RED
		_append_output(result.error, color)
		return

	var command: ConsoleCommand = result.command
	if command == null:
		return

	var ctx := _build_context()
	var output := command.execute.call(result.args, ctx)
	if output != "":
		var is_error := output.begins_with("error:")
		_append_output(output, Color.RED if is_error else Color.WHITE)


func _build_context() -> Dictionary:
	var ctx: Dictionary = {}
	var viewport := get_viewport()
	var camera := viewport.get_camera_2d()
	if camera:
		var screen_pos := viewport.get_mouse_position()
		var view_size := viewport.get_visible_rect().size
		ctx["world_pos"] = (screen_pos - view_size * 0.5) / camera.zoom + camera.global_position
	else:
		ctx["world_pos"] = Vector2.ZERO
	ctx["player"] = get_tree().get_first_node_in_group("player")
	ctx["world_manager"] = get_tree().current_scene.get_node_or_null("WorldManager") if get_tree().current_scene else null
	ctx["scene"] = get_tree().current_scene
	return ctx


func _autocomplete() -> void:
	var text := _input.text
	var cursor := _input.caret_column
	var suggestions := _registry.get_suggestions(text, cursor)

	if suggestions.is_empty():
		return

	if suggestions.size() == 1:
		var before := text.substr(0, cursor)
		var after := text.substr(cursor)
		var parts := before.rsplit(" ", true, 1)
		if parts.size() == 1:
			_input.text = suggestions[0] + " " + after
			_input.caret_column = suggestions[0].length() + 1
		else:
			_input.text = parts[0] + " " + suggestions[0] + " " + after
			_input.caret_column = parts[0].length() + 1 + suggestions[0].length() + 1
	else:
		_show_suggestions(suggestions)


func _show_suggestions(list: Array[String]) -> void:
	for child in _suggestions.get_children():
		child.queue_free()
	for item in list:
		var label := Label.new()
		label.text = item
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_suggestions.add_child(label)
	_suggestions.show()


func _on_text_changed(_new_text: String) -> void:
	_suggestions.hide()


func _cycle_history(direction: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + direction, 0, _history.size())
	if _history_index < _history.size():
		_input.text = _history[_history_index]
		_input.caret_column = _input.text.length()
	else:
		_input.clear()
	_history_index = clampi(_history_index, 0, _history.size())


func _append_output(text: String, color: Color) -> void:
	_output.append_text("[color=#" + color.to_html(false) + "]" + text + "[/color]\n")

	if _output.get_paragraph_count() > MAX_OUTPUT_LINES:
		_output.remove_paragraph(0)
