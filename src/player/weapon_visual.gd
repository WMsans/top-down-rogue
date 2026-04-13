class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

const SWING_DURATION: float = 0.25
const HALF_ARC: float = PI / 4.0

const OVERSHOOT_ANGLE: float = PI / 6.0
const SWING_PHASE_RATIO: float = 0.65
const RETURN_EASE_POWER: float = 2.5

const TRAIL_INTERVAL: float = 0.03
const TRAIL_LIFETIME: float = 0.18
const TRAIL_COLOR: Color = Color(0.3, 0.9, 1.0, 0.6)

@onready var _sprite: Sprite2D = $Sprite2D

var _is_swinging: bool = false
var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _facing_angle: float = 0.0
var _trail_timer: float = 0.0


func _ready() -> void:
	_sprite.texture = WEAPON_TEXTURE
	var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)


func _process(delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	
	_facing_angle = player.get_facing_direction().angle()
	
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _process_idle() -> void:
	position = Vector2(cos(_facing_angle), sin(_facing_angle)) * PIVOT_DISTANCE
	rotation = _facing_angle + PI / 2.0


func _process_swing(delta: float) -> void:
	_elapsed += delta
	_trail_timer += delta

	var t := _elapsed / SWING_DURATION
	if t >= 1.0:
		_is_swinging = false
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
		_process_idle()
		return

	position = Vector2.ZERO
	rotation = 0.0

	var current_angle := _get_swing_angle(t)
	_sprite.position = _get_position_at_angle(current_angle, PIVOT_DISTANCE)
	_sprite.rotation = current_angle + PI / 2.0

	if _trail_timer >= TRAIL_INTERVAL:
		_trail_timer -= TRAIL_INTERVAL
		_spawn_trail()


func _get_swing_angle(t: float) -> float:
	if t < SWING_PHASE_RATIO:
		var swing_t := t / SWING_PHASE_RATIO
		var eased_t := _elastic_out(swing_t)
		var overshoot_end: float = _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
		return lerpf(_start_angle, overshoot_end, eased_t)
	else:
		var return_t := (t - SWING_PHASE_RATIO) / (1.0 - SWING_PHASE_RATIO)
		var eased_return := ease(return_t, RETURN_EASE_POWER)
		var overshoot_end: float = _end_angle + OVERSHOOT_ANGLE * sign(_end_angle - _start_angle)
		return lerpf(overshoot_end, _facing_angle, eased_return)


func swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_elapsed = 0.0
	_trail_timer = TRAIL_INTERVAL
	_is_swinging = true


func _spawn_trail() -> void:
	var trail := Sprite2D.new()
	trail.texture = WEAPON_TEXTURE
	var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
	trail.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
	trail.modulate = TRAIL_COLOR
	get_tree().current_scene.add_child(trail)
	trail.global_position = _sprite.global_position
	trail.global_rotation = _sprite.global_rotation
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)


func _get_position_at_angle(angle: float, distance: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * distance


func _elastic_out(t: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var p := 0.3
	return pow(2.0, -10.0 * t) * sin((t - p / 4.0) * (2.0 * PI) / p) + 1.0


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null