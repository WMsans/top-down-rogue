class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/sword_01c.png")
const RANGE: float = 36.0
const ARC_ANGLE: float = PI / 2.0
const PUSH_SPEED: float = 60.0

const PIVOT_DISTANCE: float = 6.0
const HALF_ARC: float = PI / 3.5

const PREP_DURATION: float = 0.06
const ACTION_DURATION: float = 0.09
const HOLD_DURATION: float = 0.025
const RETURN_DURATION: float = 0.32

const ANTICIPATION_PULLBACK: float = PI / 5.0
const OVERSHOOT_ANGLE: float = PI / 9.0

const PREP_SCALE: Vector2 = Vector2(1.25, 0.75)
const ACTION_SCALE: Vector2 = Vector2(0.7, 1.35)
const HOLD_SCALE: Vector2 = Vector2(1.05, 0.95)

const PUNCH_DISTANCE: float = 14.0
const HOLD_DISTANCE: float = 8.0

const TRAIL_ANGLE_STEP: float = PI / 32.0
const TRAIL_LIFETIME: float = 0.15
const TRAIL_COLOR: Color = Color(2.0, 6.0, 8.0, 0.6)

const IDLE_ROTATION_SPEED: float = 10.0

enum Phase { NONE, PREP, ACTION, HOLD, RETURN }

var _is_swinging: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _swing_dir: float = 1.0
var _swing_toggle: float = 1.0
var _facing_angle: float = 0.0
var _visual_angle: float = NAN
var _last_trail_angle: float = 0.0
var _swing_angle: float = 0.0
var _swing_dist: float = PIVOT_DISTANCE
var _swing_scale: Vector2 = Vector2.ONE
var _from_angle: float = 0.0
var _from_dist: float = PIVOT_DISTANCE
var _from_scale: Vector2 = Vector2.ONE


func _init() -> void:
	name = "Melee Weapon"
	cooldown = 0.35
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
	_hit_attackables_in_arc(user, pos, direction)


func _hit_attackables_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	var dmg: int = int(damage)
	if dmg <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc: float = ARC_ANGLE / 2.0
	for node in user.get_tree().get_nodes_in_group("attackable"):
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var to_target: Vector2 = node.global_position - origin
		var dist: float = to_target.length()
		if dist > RANGE or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc:
			continue
		var hit_dir: Vector2 = to_target / dist
		node.on_hit_impact(node.global_position, hit_dir, dmg)


func _tick_impl(_delta: float) -> void:
	pass


func update_visual(delta: float, user: Node) -> void:
	if visual == null:
		return
	_facing_angle = _get_facing_direction(user).angle()
	if is_nan(_visual_angle):
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_swing_toggle = -_swing_toggle
	_swing_dir = _swing_toggle
	_start_angle = _facing_angle - HALF_ARC * _swing_dir
	_end_angle = _facing_angle + HALF_ARC * _swing_dir
	if is_nan(_visual_angle):
		_visual_angle = _facing_angle
	_swing_angle = _visual_angle
	_swing_dist = PIVOT_DISTANCE
	_swing_scale = Vector2.ONE
	_capture_from()
	_phase = Phase.PREP
	_phase_time = 0.0
	_last_trail_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
	_is_swinging = true


func _capture_from() -> void:
	_from_angle = _swing_angle
	_from_dist = _swing_dist
	_from_scale = _swing_scale


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI / 2.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _ease_out_quad(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u


func _ease_out_cubic(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


func _ease_in_out_cubic(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x < 0.5:
		return 4.0 * x * x * x
	var u := -2.0 * x + 2.0
	return 1.0 - u * u * u / 2.0


func _ease_out_elastic(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	const C: float = (2.0 * PI) / 3.0
	return pow(2.0, -10.0 * x) * sin((x * 10.0 - 0.75) * C) + 1.0


func _process_swing(_delta: float) -> void:
	_phase_time += _delta

	var target_angle: float = _facing_angle
	var target_dist: float = PIVOT_DISTANCE
	var target_scale: Vector2 = Vector2.ONE
	var eased: float = 0.0
	var t: float = 0.0

	match _phase:
		Phase.PREP:
			t = _phase_time / PREP_DURATION
			eased = _ease_out_quad(t)
			target_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
			target_dist = PIVOT_DISTANCE * 0.85
			target_scale = PREP_SCALE
			if t >= 1.0:
				_apply_pose(target_angle, target_dist, target_scale)
				_capture_from()
				_phase = Phase.ACTION
				_phase_time = 0.0
				_last_trail_angle = _swing_angle
				return

		Phase.ACTION:
			t = _phase_time / ACTION_DURATION
			eased = _ease_out_cubic(t)
			target_angle = _end_angle + OVERSHOOT_ANGLE * _swing_dir
			target_dist = PUNCH_DISTANCE
			target_scale = ACTION_SCALE
			if t >= 1.0:
				_apply_pose(target_angle, target_dist, target_scale)
				_capture_from()
				_phase = Phase.HOLD
				_phase_time = 0.0
				return

		Phase.HOLD:
			t = _phase_time / HOLD_DURATION
			eased = _ease_in_out_cubic(t)
			target_angle = _end_angle
			target_dist = HOLD_DISTANCE
			target_scale = HOLD_SCALE
			if t >= 1.0:
				_apply_pose(target_angle, target_dist, target_scale)
				_capture_from()
				_phase = Phase.RETURN
				_phase_time = 0.0
				return

		Phase.RETURN:
			t = _phase_time / RETURN_DURATION
			eased = _ease_out_elastic(t)
			target_angle = _facing_angle
			target_dist = PIVOT_DISTANCE
			target_scale = Vector2.ONE
			if t >= 1.0:
				_is_swinging = false
				_visual_angle = _facing_angle
				_process_idle()
				return

		_:
			_is_swinging = false
			_process_idle()
			return

	_swing_angle = lerp_angle(_from_angle, target_angle, eased)
	_swing_dist = lerpf(_from_dist, target_dist, eased)
	_swing_scale = _from_scale.lerp(target_scale, eased)

	_apply_pose(_swing_angle, _swing_dist, _swing_scale)

	if _phase == Phase.ACTION:
		var progress := angle_difference(_last_trail_angle, _swing_angle) * _swing_dir
		var max_spawns := 8
		while progress >= TRAIL_ANGLE_STEP and max_spawns > 0:
			_last_trail_angle += TRAIL_ANGLE_STEP * _swing_dir
			progress -= TRAIL_ANGLE_STEP
			max_spawns -= 1
			_spawn_trail_at_angle(_last_trail_angle)


func _apply_pose(angle: float, dist: float, scl: Vector2) -> void:
	visual.position = Vector2.ZERO
	visual.rotation = 0.0
	_sprite.position = Vector2(cos(angle), sin(angle)) * dist
	_sprite.rotation = angle + PI / 2.0
	_sprite.scale = scl


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
	trail.global_rotation = visual.global_rotation + angle + PI / 2.0
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
