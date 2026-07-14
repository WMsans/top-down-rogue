class_name CameraEffect
extends Node

var _cam: Camera2D = null
var _rest_offset: Vector2 = Vector2.ZERO
var _rest_zoom: Vector2 = Vector2.ONE
var _shake_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(cam: Camera2D) -> void:
	_cam = cam
	_rest_offset = cam.offset
	_rest_zoom = cam.zoom


func pan_to(world_pos: Vector2, duration: float, zoom: Vector2) -> Tween:
	if _cam == null:
		return null
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var target := world_pos - screen_center - _cam.global_position
	var t := create_tween()
	t.tween_property(_cam, "offset", target, duration).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_cam, "zoom", zoom, duration).set_trans(Tween.TRANS_SINE)
	return t


func pan_back(duration: float) -> Tween:
	if _cam == null:
		return null
	var t := create_tween()
	t.tween_property(_cam, "offset", _rest_offset, duration).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(_cam, "zoom", _rest_zoom, duration).set_trans(Tween.TRANS_SINE)
	return t


func shake(intensity: float, duration: float) -> void:
	if _cam == null:
		return
	if _shake_tween and _shake_tween.is_running():
		_shake_tween.kill()
	var timer := 0.0
	var tw := create_tween()
	_shake_tween = tw
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	for _i in int(duration * 60.0):
		tw.tween_callback(func():
			if _cam == null or not is_instance_valid(_cam): return
			_cam.offset += Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)))
		tw.tween_interval(1.0 / 60.0)
	var fade := create_tween()
	fade.tween_property(_cam, "offset", _rest_offset, duration).set_trans(Tween.TRANS_LINEAR)


func hit_stop(duration: float) -> void:
	get_tree().paused = true
	get_tree().create_timer(duration, true, false, true).timeout.connect(func():
		get_tree().paused = false)
