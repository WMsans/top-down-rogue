class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

const SWING_DURATION: float = 0.25
const HALF_ARC: float = PI / 4.0
const TRAIL_COUNT: int = 4
const TRAIL_DELAY: float = 0.08
const TRAIL_COLORS: Array[Color] = [
	Color(0.3, 0.9, 1.0, 0.7),
	Color(0.4, 0.6, 1.0, 0.5),
	Color(0.7, 0.4, 1.0, 0.35),
	Color(1.0, 1.0, 1.0, 0.2)
]

const OVERSHOOT_ANGLE: float = PI / 6.0
const SWING_PHASE_RATIO: float = 0.65
const RETURN_EASE_POWER: float = 2.5

@onready var _sprite: Sprite2D = $Sprite2D

var _is_swinging: bool = false
var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _facing_angle: float = 0.0
var _trails: Array[Sprite2D] = []


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
	
	var t := _elapsed / SWING_DURATION
	if t >= 1.0:
		_is_swinging = false
		_clear_trails()
		_process_idle()
		return
	
	var eased_t := ease(t, 2.0)
	var current_angle := lerpf(_start_angle, _end_angle, eased_t)
	
	_sprite.position = _get_position_at_angle(current_angle, PIVOT_DISTANCE)
	_sprite.rotation = current_angle + PI / 2.0
	
	_update_trails(t)


func swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_elapsed = 0.0
	_is_swinging = true
	_spawn_trails()


func _spawn_trails() -> void:
	_clear_trails()
	for i in range(TRAIL_COUNT):
		var trail := Sprite2D.new()
		trail.texture = WEAPON_TEXTURE
		trail.modulate = TRAIL_COLORS[i]
		var tex_size: Vector2 = WEAPON_TEXTURE.get_size()
		trail.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
		trail.position = _get_position_at_angle(_start_angle, PIVOT_DISTANCE)
		trail.rotation = _start_angle + PI / 2.0
		add_child(trail)
		_trails.append(trail)


func _clear_trails() -> void:
	for trail in _trails:
		trail.queue_free()
	_trails.clear()


func _update_trails(t: float) -> void:
	var fade_alpha := 1.0 - t
	
	for i in range(TRAIL_COUNT):
		var trail := _trails[i]
		var trail_t: float = max(0.0, t - TRAIL_DELAY * float(i + 1))
		if trail_t > 0:
			var trail_eased := ease(trail_t, 2.0)
			var trail_angle := lerpf(_start_angle, _end_angle, trail_eased)
			trail.position = _get_position_at_angle(trail_angle, PIVOT_DISTANCE)
			trail.rotation = trail_angle + PI / 2.0
		
		var base_color := TRAIL_COLORS[i]
		trail.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade_alpha)


func _get_position_at_angle(angle: float, distance: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * distance


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null