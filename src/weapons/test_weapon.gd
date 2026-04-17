class_name TestWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/candy_02c.png")
const GAS_RADIUS: float = 6.0
const GAS_DENSITY: int = 200

const PIVOT_DISTANCE: float = 6.0
const BOUNCE_UP_DURATION: float = 0.1
const BOUNCE_DOWN_DURATION: float = 0.15
const BOUNCE_SCALE_UP: Vector2 = Vector2(1.4, 1.4)
const BOUNCE_SETTLE: Vector2 = Vector2(1.08, 1.08)
const LERP_SNAP: float = 16.0
const LERP_EASE: float = 6.0
const IDLE_ROTATION_SPEED: float = 10.0

enum Phase { NONE, UP, DOWN }

var _cooldown_timer: float = 0.0
var _is_bouncing: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _visual_angle: float = NAN
var _bounce_scale: Vector2 = Vector2.ONE
var _facing_angle: float = 0.0


func _init() -> void:
	name = "Test Weapon"
	cooldown = 0.5
	damage = 1.0
	icon_texture = WEAPON_TEXTURE


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(0, -tex_size.y / 2.0)


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return

	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return

	var pos: Vector2 = _sprite.global_position if _sprite else user.global_position
	world_manager.place_gas(pos, GAS_RADIUS, GAS_DENSITY)
	_start_bounce()
	_cooldown_timer = cooldown


func tick(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func is_ready() -> bool:
	return _cooldown_timer <= 0.0


func update_visual(delta: float, user: Node) -> void:
	if visual == null:
		return

	_facing_angle = _get_facing_direction(user).angle()

	if _visual_angle != _visual_angle:
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))

	if _is_bouncing:
		_process_bounce(delta)
	else:
		_process_idle()


func _start_bounce() -> void:
	_bounce_scale = Vector2.ONE
	_phase = Phase.UP
	_phase_time = 0.0
	_is_bouncing = true


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _process_bounce(delta: float) -> void:
	_phase_time += delta

	var target_scale: Vector2 = Vector2.ONE
	var scale_speed: float = LERP_EASE

	match _phase:
		Phase.UP:
			target_scale = BOUNCE_SCALE_UP
			scale_speed = LERP_SNAP
			if _phase_time >= BOUNCE_UP_DURATION:
				_phase = Phase.DOWN
				_phase_time = 0.0

		Phase.DOWN:
			var settle_decay := maxf(0.0, 1.0 - _phase_time / BOUNCE_DOWN_DURATION)
			target_scale = Vector2.ONE + (BOUNCE_SETTLE - Vector2.ONE) * settle_decay
			scale_speed = LERP_SNAP
			if _phase_time >= BOUNCE_DOWN_DURATION:
				_is_bouncing = false
				_bounce_scale = Vector2.ONE
				_process_idle()
				return

		_:
			_is_bouncing = false
			_bounce_scale = Vector2.ONE
			_process_idle()
			return

	var scale_factor: float = 1.0 - exp(-scale_speed * delta)
	_bounce_scale = _bounce_scale.lerp(target_scale, scale_factor)

	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = _bounce_scale


func _get_world_manager(user: Node) -> Node:
	if user.has_method("get_world_manager"):
		return user.get_world_manager()
	var parent := user.get_parent()
	if parent:
		return parent.get_node_or_null("WorldManager")
	return null


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
