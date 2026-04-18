class_name UiAnimations

static func bounce_on_hover(control: Control, scale_up: float = 1.05, duration: float = 0.15) -> Tween:
	_update_pivot_center(control)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2(scale_up, scale_up), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

static func bounce_on_press(control: Control, scale_down: float = 0.95, duration: float = 0.1) -> Tween:
	_update_pivot_center(control)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2(scale_down, scale_down), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	return tween

static func reset_scale(control: Control, duration: float = 0.15) -> Tween:
	_update_pivot_center(control)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

static func slide_in_up(control: Control, pixels: float = 30.0, duration: float = 0.3) -> Tween:
	var target_pos := control.position
	control.position.y += pixels
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.parallel().tween_property(control, "position:y", target_pos.y, duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func fade_in(control: Control, duration: float = 0.3, delay: float = 0.0) -> Tween:
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func fade_overlay(control: ColorRect, target_alpha: float, duration: float = 0.25) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(control, "color:a", target_alpha, duration).set_trans(Tween.TRANS_LINEAR)
	return tween

static func pulse_glow(control: Control, property: String, from: float, to: float, duration: float = 1.5) -> Tween:
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_loops()
	tween.tween_property(control, property, to, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(control, property, from, duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween

static func stagger_slide_in(controls: Array[Control], delay_between: float = 0.1, pixels: float = 20.0, duration: float = 0.3) -> void:
	for i in controls.size():
		var control := controls[i]
		control.position.y += pixels
		control.modulate.a = 0.0
		var tween := control.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		if i > 0:
			tween.tween_interval(delay_between * i)
		tween.parallel().tween_property(control, "position:y", control.position.y - pixels, duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(control, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_LINEAR)

static func setup_button_hover(button: Button, scale_up: float = 1.05, press_scale: float = 0.95) -> void:
	_update_pivot_center(button)
	button.resized.connect(func() -> void:
		_update_pivot_center(button)
	)
	button.mouse_entered.connect(func() -> void:
		if not button.button_pressed:
			bounce_on_hover(button, scale_up)
	)
	button.mouse_exited.connect(func() -> void:
		reset_scale(button)
	)
	button.button_down.connect(func() -> void:
		bounce_on_press(button, press_scale)
	)
	button.button_up.connect(func() -> void:
		reset_scale(button)
	)

static func _update_pivot_center(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
