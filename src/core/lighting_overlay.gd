extends ColorRect


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	visible = LightingManager.enabled
	if not visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var view_size: Vector2 = vp.get_visible_rect().size / cam.zoom
	var origin: Vector2 = cam.get_screen_center_position() - view_size * 0.5
	RenderingServer.global_shader_parameter_set("light_camera_origin", origin)
	RenderingServer.global_shader_parameter_set("light_camera_size", view_size)
