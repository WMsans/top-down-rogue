class_name WeaponInfoPopup
extends CanvasLayer

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const POPUP_OFFSET: float = 14.0
const REST_SCALE: float = 0.38
const SHOW_START_SCALE: float = 0.15
const HIDE_END_SCALE: float = 0.2
const SHOW_DURATION: float = 0.45
const HIDE_DURATION: float = 0.18

var _card: Card
var _scale_tween: Tween
var _fade_tween: Tween
var _current_drop: WeaponDrop = null
var _shown: bool = false
var _hiding: bool = false


func _ready() -> void:
	layer = 15

	_card = CARD_SCENE.instantiate()
	_card.is_selectable = false
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_card.scale = Vector2(SHOW_START_SCALE, SHOW_START_SCALE)
	_card.visible = false
	add_child(_card)
	_card.set_process(false)

	var svc := _card.get_node("SubViewportContainer") as SubViewportContainer
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func show_for(drop: WeaponDrop) -> void:
	if not is_instance_valid(drop) or drop.weapon == null:
		dismiss()
		return
	if _current_drop == drop and _shown and not _hiding:
		return
	_current_drop = drop
	_populate(drop.weapon)
	_shown = true
	_hiding = false
	_card.visible = true
	_animate_show()


func dismiss() -> void:
	if _hiding or (not _shown and not _card.visible):
		return
	_shown = false
	_hiding = true
	_current_drop = null
	_animate_hide()


func is_shown() -> bool:
	return _shown


func update_position(drop: WeaponDrop, player: Node2D = null) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var xform := cam.get_canvas_transform()
	var drop_screen := xform * drop.global_position
	var visual_size := _card.card_size * REST_SCALE
	var viewport_size := get_viewport().get_visible_rect().size
	const MARGIN := 4.0

	var dir := Vector2.UP
	if player != null and is_instance_valid(player):
		var player_screen := xform * player.global_position
		var delta := drop_screen - player_screen
		if delta.length_squared() > 0.01:
			dir = delta.normalized()

	var push: float = POPUP_OFFSET + (visual_size.x * 0.5 if absf(dir.x) > absf(dir.y) else visual_size.y * 0.5)
	var pivot_screen := drop_screen + dir * push

	pivot_screen.x = clampf(
		pivot_screen.x,
		MARGIN + visual_size.x * 0.5,
		viewport_size.x - MARGIN - visual_size.x * 0.5
	)
	pivot_screen.y = clampf(
		pivot_screen.y,
		MARGIN + visual_size.y * 0.5,
		viewport_size.y - MARGIN - visual_size.y * 0.5
	)

	_card.position = pivot_screen - _card.pivot_offset


func _populate(weapon: Weapon) -> void:
	var stats: Array[String] = []
	if weapon.has_method("get_base_stats"):
		var base_stats: Dictionary = weapon.get_base_stats()
		stats.append("Cooldown: %.2fs" % float(base_stats.get("cooldown", weapon.cooldown)))
		stats.append("Damage: %.0f" % float(base_stats.get("damage", weapon.damage)))
	else:
		stats.append("Cooldown: %.2fs" % weapon.cooldown)
		stats.append("Damage: %.0f" % weapon.damage)

	var mod_icons: Array[Texture2D] = []
	for i in range(weapon.modifier_slot_count):
		var mod: Modifier = weapon.get_modifier_at(i)
		mod_icons.append(mod.icon_texture if mod else null)

	_card.populate(weapon.icon_texture, weapon.name, stats, mod_icons)


func _animate_show() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_card.scale = Vector2(SHOW_START_SCALE, SHOW_START_SCALE)

	_scale_tween = create_tween()
	_scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scale_tween.tween_property(_card, "scale", Vector2(REST_SCALE, REST_SCALE), SHOW_DURATION)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_card, "modulate:a", 1.0, 0.18)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _animate_hide() -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

	_scale_tween = create_tween()
	_scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scale_tween.tween_property(_card, "scale", Vector2(HIDE_END_SCALE, HIDE_END_SCALE), HIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_card, "modulate:a", 0.0, HIDE_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(func() -> void:
		_card.visible = false
		_hiding = false
	)
