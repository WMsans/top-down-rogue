@tool
extends EditorPlugin


var _inspector_plugin: EditorInspectorPlugin
var _last_selected_preview: WorldPreview = null


func _enter_tree() -> void:
	_inspector_plugin = WorldPreviewInspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)


func _handles(object: Object) -> bool:
	return object is WorldPreview


func _edit(object: Object) -> void:
	var preview := object as WorldPreview
	if preview == null:
		if _last_selected_preview and is_instance_valid(_last_selected_preview):
			_last_selected_preview.clear_preview()
		_last_selected_preview = null
	else:
		_last_selected_preview = preview


class WorldPreviewInspectorPlugin extends EditorInspectorPlugin:
	func _can_handle(object: Object) -> bool:
		return object is WorldPreview


	func _parse_begin(object: Object) -> void:
		var preview := object as WorldPreview
		if not preview:
			return

		var vbox := VBoxContainer.new()

		var generate_btn := Button.new()
		generate_btn.text = "Generate Preview"
		generate_btn.pressed.connect(_on_generate_pressed.bind(preview))
		vbox.add_child(generate_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear Preview"
		clear_btn.pressed.connect(_on_clear_pressed.bind(preview))
		vbox.add_child(clear_btn)

		add_custom_control(vbox)


	func _on_generate_pressed(preview: WorldPreview) -> void:
		preview.generate_preview()


	func _on_clear_pressed(preview: WorldPreview) -> void:
		preview.clear_preview()