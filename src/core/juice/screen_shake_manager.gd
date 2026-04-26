extends Node

const SHAKE_AMOUNT: float = 3.0
const SHAKE_DURATION: float = 0.18

var _amount: float = 0.0
var _duration: float = 0.0
var _elapsed: float = 0.0
var _dir_bias: Vector2 = Vector2.ZERO
var _camera: Camera2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func shake(amount: float, duration: float, dir: Vector2 = Vector2.ZERO) -> void:
	_amount = amount
	_duration = duration
	_elapsed = 0.0
	_dir_bias = dir
	_camera = get_viewport().get_camera_2d()


func _process(delta: float) -> void:
	if _camera == null or _duration <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_camera.offset = Vector2.ZERO
		_duration = 0.0
		return
	var t: float = 1.0 - (_elapsed / _duration)
	var current: float = _amount * t
	var rand_offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
	var bias := _dir_bias * 0.5 * current
	_camera.offset = rand_offset + bias
