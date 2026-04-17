class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/sword_01c.png")
const RANGE: float = 24.0
const ARC_ANGLE: float = PI / 2.0
const PUSH_SPEED: float = 60.0

const PIVOT_DISTANCE: float = 6.0
const HALF_ARC: float = PI / 3.5

const PREP_DURATION: float = 0.08
const ACTION_DURATION: float = 0.12
const SETTLE_DURATION: float = 0.18
const RETURN_DURATION: float = 0.22

const ANTICIPATION_PULLBACK: float = PI / 6.0
const OVERSHOOT_ANGLE: float = PI / 4.0
const SETTLE_BOUNCE_AMOUNT: float = PI / 12.0
const SETTLE_BOUNCE_FREQ: float = 28.0

const PREP_SCALE: Vector2 = Vector2(1.25, 0.75)
const ACTION_SCALE: Vector2 = Vector2(0.7, 1.35)
const SETTLE_SCALE: Vector2 = Vector2(1.1, 0.92)

const PUNCH_DISTANCE: float = 14.0

const LERP_SNAP: float = 16.0
const LERP_SMOOTH: float = 10.0
const LERP_EASE: float = 6.0

const TRAIL_ANGLE_STEP: float = PI / 32.0
const TRAIL_LIFETIME: float = 0.15
const TRAIL_COLOR: Color = Color(2.0, 6.0, 8.0, 0.6)

enum Phase { NONE, PREP, ACTION, SETTLE, RETURN }

var _is_swinging: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _swing_dir: float = 1.0
var _facing_angle: float = 0.0
var _visual_angle: float = NAN
var _last_trail_angle: float = 0.0
var _swing_angle: float = 0.0
var _swing_dist: float = PIVOT_DISTANCE
var _swing_scale: Vector2 = Vector2.ONE

const IDLE_ROTATION_SPEED: float = 10.0


func _init() -> void:
	name = "Melee Weapon"
	cooldown = 0.5
	damage = 5.0
	icon_texture = WEAPON_TEXTURE
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(0, -tex_size.y / 2.0)


func _use_impl(user: Node) -> void:
	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	var materials: Array[int] = MaterialRegistry.get_fluids()
	world_manager.clear_and_push_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, 0.25, materials)


func _tick_impl(_delta: float) -> void:
	pass


func update_visual(delta: float, user: Node) -> void:
	if visual == null:
		return
	_facing_angle = _get_facing_direction(user).angle()
	if _visual_angle != _visual_angle:
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_swing_dir = signf(_end_angle - _start_angle)
	_swing_angle = _visual_angle
	_swing_dist = PIVOT_DISTANCE
	_swing_scale = Vector2.ONE
	_phase = Phase.PREP
	_phase_time = 0.0
	_last_trail_angle = _swing_angle
	_is_swinging = true


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI * 3.0 / 4.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _process_swing(delta: float) -> void:
	_phase_time += delta

	var target_angle: float = _facing_angle
	var target_dist: float = PIVOT_DISTANCE
	var target_scale: Vector2 = Vector2.ONE
	var angle_speed: float = LERP_SMOOTH
	var dist_speed: float = LERP_SMOOTH
	var scale_speed: float = LERP_SMOOTH

	match _phase:
		Phase.PREP:
			target_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
			target_dist = PIVOT_DISTANCE * 0.85
			target_scale = PREP_SCALE
			angle_speed = LERP_SMOOTH
			dist_speed = LERP_SMOOTH
			scale_speed = LERP_SMOOTH
			if _phase_time >= PREP_DURATION:
				_phase = Phase.ACTION
				_phase_time = 0.0
				_last_trail_angle = _swing_angle

		Phase.ACTION:
			target_angle = _end_angle + OVERSHOOT_ANGLE * _swing_dir
			target_dist = PUNCH_DISTANCE
			target_scale = ACTION_SCALE
			angle_speed = LERP_SNAP
			dist_speed = LERP_SNAP
			scale_speed = LERP_SNAP
			if _phase_time >= ACTION_DURATION:
				_phase = Phase.SETTLE
				_phase_time = 0.0

		Phase.SETTLE:
			var decay := maxf(0.0, 1.0 - _phase_time / SETTLE_DURATION)
			target_angle = _end_angle + sin(_phase_time * SETTLE_BOUNCE_FREQ) * SETTLE_BOUNCE_AMOUNT * decay * _swing_dir
			target_dist = PIVOT_DISTANCE
			target_scale = Vector2.ONE + (SETTLE_SCALE - Vector2.ONE) * decay
			angle_speed = LERP_SMOOTH
			dist_speed = LERP_SMOOTH
			scale_speed = LERP_SMOOTH
			if _phase_time >= SETTLE_DURATION:
				_phase = Phase.RETURN
				_phase_time = 0.0

		Phase.RETURN:
			target_angle = _facing_angle
			target_dist = PIVOT_DISTANCE
			target_scale = Vector2.ONE
			angle_speed = LERP_EASE
			dist_speed = LERP_EASE
			scale_speed = LERP_EASE
			if _phase_time >= RETURN_DURATION:
				_is_swinging = false
				_visual_angle = _swing_angle
				_process_idle()
				return

		_:
			_is_swinging = false
			_process_idle()
			return

	var angle_factor: float = 1.0 - exp(-angle_speed * delta)
	var dist_factor: float = 1.0 - exp(-dist_speed * delta)
	var scale_factor: float = 1.0 - exp(-scale_speed * delta)

	_swing_angle = lerp_angle(_swing_angle, target_angle, angle_factor)
	_swing_dist = lerpf(_swing_dist, target_dist, dist_factor)
	_swing_scale = _swing_scale.lerp(target_scale, scale_factor)

	visual.position = Vector2.ZERO
	visual.rotation = 0.0
	_sprite.position = Vector2(cos(_swing_angle), sin(_swing_angle)) * _swing_dist
	_sprite.rotation = _swing_angle + PI * 3.0 / 4.0
	_sprite.scale = _swing_scale

	if _phase == Phase.ACTION or _phase == Phase.SETTLE:
		var progress := angle_difference(_last_trail_angle, _swing_angle) * _swing_dir
		var max_spawns := 8
		while progress >= TRAIL_ANGLE_STEP and max_spawns > 0:
			_last_trail_angle += TRAIL_ANGLE_STEP * _swing_dir
			progress -= TRAIL_ANGLE_STEP
			max_spawns -= 1
			_spawn_trail_at_angle(_last_trail_angle)


func _spawn_trail_at_angle(angle: float) -> void:
	var trail := Sprite2D.new()
	trail.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	trail.offset = Vector2(0, -tex_size.y / 2.0)
	trail.modulate = TRAIL_COLOR
	trail.z_index = -1
	trail.z_as_relative = false
	visual.get_tree().current_scene.add_child(trail)
	var local_pos := Vector2(cos(angle), sin(angle)) * _swing_dist
	trail.global_position = visual.global_position + local_pos.rotated(visual.global_rotation)
	trail.global_rotation = visual.global_rotation + angle + PI * 3.0 / 4.0
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)


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