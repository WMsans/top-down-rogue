class_name EnemyAnimator
extends Node

enum Hold { NONE, BREATHE, NORMAL }

const IDLE_INTERVAL: float = 0.6
const MIN_MOVING_INTERVAL: float = 0.12

@export var texture_normal: Texture2D = null
@export var texture_breathe: Texture2D = null

var _hold: int = Hold.NONE
var _timer: float = 0.0
var _showing_breathe: bool = false
var _sprite: Sprite2D = null


func _ready() -> void:
	_sprite = get_parent().get_node_or_null("Sprite2D")


func set_textures(normal: Texture2D, breathe: Texture2D) -> void:
	texture_normal = normal
	texture_breathe = breathe


func set_hold(mode: int) -> void:
	if _hold == mode:
		return
	_hold = mode
	if mode == Hold.BREATHE:
		_apply_frame(true)
	elif mode == Hold.NORMAL:
		_apply_frame(false)


func tick(delta: float, is_moving: bool, speed_ratio: float) -> void:
	if texture_normal == null or texture_breathe == null:
		return
	if _hold != Hold.NONE:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = _flicker_interval(is_moving, speed_ratio)
		_apply_frame(not _showing_breathe)


func _flicker_interval(is_moving: bool, speed_ratio: float) -> float:
	if not is_moving:
		return IDLE_INTERVAL
	var t: float = clampf(speed_ratio, 0.0, 1.0)
	return lerpf(IDLE_INTERVAL, MIN_MOVING_INTERVAL, t)


func _apply_frame(show_breathe: bool) -> void:
	_showing_breathe = show_breathe
	if _sprite == null:
		return
	_sprite.texture = texture_breathe if show_breathe else texture_normal
