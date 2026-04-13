class_name MeleeSwingEffect
extends Node2D

const SWING_DURATION: float = 0.25
const HALF_ARC: float = PI / 4.0
const BLADE_DISTANCE: float = 20.0
const TRAIL_COUNT: int = 4

const TRAIL_COLORS: Array[Color] = [
	Color(0.3, 0.9, 1.0, 0.7),
	Color(0.4, 0.6, 1.0, 0.5),
	Color(0.7, 0.4, 1.0, 0.35),
	Color(1.0, 1.0, 1.0, 0.2)
]

@onready var _trails_container: Node2D = $Trails

var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _weapon_texture: Texture2D = null
var _trails: Array[Sprite2D] = []


func setup(direction: Vector2, texture: Texture2D) -> void:
	_weapon_texture = texture
	_start_angle = direction.angle() - HALF_ARC
	_end_angle = direction.angle() + HALF_ARC
	_spawn_trails()


func _spawn_trails() -> void:
	for i in range(TRAIL_COUNT):
		var sprite := Sprite2D.new()
		sprite.texture = _weapon_texture
		sprite.modulate = TRAIL_COLORS[i]
		var tex_size: Vector2 = _weapon_texture.get_size()
		sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
		sprite.position = _get_position_at_angle(_start_angle)
		sprite.rotation = _start_angle + PI / 2.0
		_trails_container.add_child(sprite)
		_trails.append(sprite)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / SWING_DURATION
	
	if t >= 1.0:
		queue_free()
		return
	
	var eased_t := ease(t, 2.0)
	var current_angle := lerpf(_start_angle, _end_angle, eased_t)
	
	var last_trail := _trails[TRAIL_COUNT - 1]
	last_trail.position = _get_position_at_angle(current_angle)
	last_trail.rotation = current_angle + PI / 2.0
	
	var fade_alpha := 1.0 - t
	for i in range(TRAIL_COUNT):
		var trail := _trails[i]
		var base_color := TRAIL_COLORS[i]
		trail.modulate = Color(base_color.r, base_color.g, base_color.b, base_color.a * fade_alpha)


func _get_position_at_angle(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle)) * BLADE_DISTANCE