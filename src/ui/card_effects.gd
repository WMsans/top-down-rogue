# src/ui/card_effects.gd
class_name CardEffects

const HOLO_SHADER := preload("res://shaders/ui/card_holo.gdshader")
const DEFAULT_TILT_STRENGTH := 0.08
const DEFAULT_HOVER_SCALE := 1.05

static var _controllers: Dictionary = {}

static func setup_card(card: Control, tilt_strength := DEFAULT_TILT_STRENGTH, hover_scale := DEFAULT_HOVER_SCALE) -> CardEffectController:
	if card.custom_minimum_size.x == 0.0 or card.custom_minimum_size.y == 0.0:
		push_error("CardEffects.setup_card: card has zero minimum size")
		return null

	var controller := CardEffectController.new()
	controller.card = card
	controller.tilt_strength = tilt_strength
	controller.hover_scale = hover_scale

	# 1. Create SubViewport
	var subviewport := SubViewport.new()
	subviewport.name = "CardEffectViewport"
	subviewport.transparent_bg = true
	subviewport.size = card.custom_minimum_size
	subviewport.gui_disable_input = false
	subviewport.handle_input_locally = false
	card.add_child(subviewport)
	controller.subviewport = subviewport

	# Reparent original children into a VBoxContainer inside the SubViewport
	var inner_container := VBoxContainer.new()
	inner_container.name = "InnerContainer"
	inner_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	subviewport.add_child(inner_container)

	for child in card.get_children().duplicate():
		if child != subviewport and child != controller:
			card.remove_child(child)
			inner_container.add_child(child)

	# 2. Create TextureRect to display the rendered SubViewport
	var texture_rect := TextureRect.new()
	texture_rect.name = "CardEffectTextureRect"
	texture_rect.anchors_preset = Control.PRESET_FULL_RECT
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = subviewport.get_texture()
	card.add_child(texture_rect)
	controller.texture_rect = texture_rect

	# 3. Create ShaderMaterial and assign
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = HOLO_SHADER
	shader_mat.set_shader_parameter("card_size", card.custom_minimum_size)
	shader_mat.set_shader_parameter("border_width", 0.06)
	shader_mat.set_shader_parameter("tilt_x", 0.0)
	shader_mat.set_shader_parameter("tilt_y", 0.0)
	shader_mat.set_shader_parameter("holo_time", 0.0)
	shader_mat.set_shader_parameter("holo_intensity", 0.0)
	texture_rect.material = shader_mat

	# Add controller as child (handles signals and _process)
	card.add_child(controller)
	if card.is_inside_tree():
		controller._init_signals()

	_controllers[card] = controller
	return controller

static func get_controller(card: Control) -> CardEffectController:
	return _controllers.get(card, null)


class CardEffectController:
	extends Node

	var card: Control = null
	var subviewport: SubViewport = null
	var texture_rect: TextureRect = null
	var tilt_strength: float = DEFAULT_TILT_STRENGTH
	var hover_scale: float = DEFAULT_HOVER_SCALE
	var _hover_tween: Tween = null
	var _icon_zones: Array[Dictionary] = []
	var _active_zone: String = ""

	signal zone_entered(zone_id: String)
	signal zone_exited()

	func _ready() -> void:
		_init_signals()

	func _init_signals() -> void:
		if card.mouse_entered.is_connected(_on_hover_enter):
			return
		card.mouse_entered.connect(_on_hover_enter)
		card.mouse_exited.connect(_on_hover_leave)
		card.tree_exiting.connect(_cleanup)
		set_process(true)

	func _process(_delta: float) -> void:
		var mat := texture_rect.material as ShaderMaterial
		if mat == null:
			return

		var mouse_pos := card.get_local_mouse_position()
		var delta := (mouse_pos - card.size * 0.5) / (card.size * 0.5)

		mat.set_shader_parameter("tilt_x", delta.y * tilt_strength)
		mat.set_shader_parameter("tilt_y", -delta.x * tilt_strength)
		mat.set_shader_parameter("holo_time", fmod(Time.get_ticks_msec() / 1000.0, 1.0))

		# Update SubViewport size if card resized
		if subviewport.size != card.custom_minimum_size:
			subviewport.size = card.custom_minimum_size
			mat.set_shader_parameter("card_size", card.custom_minimum_size)

		# Icon zone hit testing
		_check_icon_zones(mouse_pos)

	func register_zone(zone_id: String, rect: Rect2) -> void:
		_icon_zones.append({"id": zone_id, "rect": rect})

	func clear_zones() -> void:
		_icon_zones.clear()
		_active_zone = ""

	func _check_icon_zones(mouse_pos: Vector2) -> void:
		var found: String = ""
		for zone_dict in _icon_zones:
			var rect: Rect2 = zone_dict["rect"]
			if rect.has_point(mouse_pos):
				found = zone_dict["id"]
				break
		if found != _active_zone:
			if not _active_zone.is_empty():
				zone_exited.emit()
			_active_zone = found
			if not found.is_empty():
				zone_entered.emit(found)

	func _on_hover_enter() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()

		var t := card.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

		t.tween_property(card, "scale", Vector2(hover_scale, hover_scale), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "rotation", deg_to_rad(2.0), 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 1.0, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		t.tween_property(card, "scale", Vector2(1.03, 1.03), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_property(card, "rotation", 0.0, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)

		_hover_tween = t

	func _on_hover_leave() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()

		var t := card.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

		t.tween_property(card, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "rotation", 0.0, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		t.parallel().tween_method(_set_holo_intensity, _get_holo_intensity(), 0.0, 0.2) \
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)

		_hover_tween = t

	func _set_holo_intensity(v: float) -> void:
		var mat := texture_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("holo_intensity", v)

	func _get_holo_intensity() -> float:
		var mat := texture_rect.material as ShaderMaterial
		if mat:
			return mat.get_shader_parameter("holo_intensity")
		return 0.0

	func _cleanup() -> void:
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = null
		if card.mouse_entered.is_connected(_on_hover_enter):
			card.mouse_entered.disconnect(_on_hover_enter)
		if card.mouse_exited.is_connected(_on_hover_leave):
			card.mouse_exited.disconnect(_on_hover_leave)
		if card.tree_exiting.is_connected(_cleanup):
			card.tree_exiting.disconnect(_cleanup)
		CardEffects._controllers.erase(card)
