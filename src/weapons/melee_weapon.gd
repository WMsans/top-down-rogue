class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/Weapons/sword_01c.png")
const RANGE: float = 36.0
const ARC_ANGLE: float = PI / 2.0
const PUSH_SPEED: float = 60.0

# Sprite is 18x18 with pommel at (15, 15) and blade pointing top-left.
# Shift the texture so the pommel sits at the sprite origin (the rotation pivot),
# and remember the blade's local direction at rotation=0 for converting blade
# angles into sprite rotations.
const POMMEL_PIXEL: Vector2 = Vector2(15.0, 15.0)
const LOCAL_BLADE_ANGLE: float = -3.0 * PI / 4.0
const HALF_ARC: float = PI / 3.5
const IDLE_ROTATION_SPEED: float = 10.0

const PREP_DURATION: float = 0.06
const ACTION_DURATION: float = 0.09
const HOLD_DURATION: float = 0.025
const RETURN_DURATION: float = 0.32

const ANTICIPATION_PULLBACK: float = PI / 5.0
const OVERSHOOT_ANGLE: float = PI / 9.0

const PREP_SCALE: Vector2 = Vector2(1.25, 0.75)
const ACTION_SCALE: Vector2 = Vector2(0.7, 1.35)
const HOLD_SCALE: Vector2 = Vector2(1.05, 0.95)

# Pommel rests above the player body; small forward shifts drive the swing's
# weight transfer while the blade rotation does the visible work.
const REST_ABOVE: float = 0.0
const REST_FORWARD: float = 3.0
const PIVOT_BACK: float = 2.0
const PIVOT_PUNCH: float = 4.0
const PIVOT_HOLD: float = 3.0

const TRAIL_ANGLE_STEP: float = PI / 32.0
const TRAIL_LIFETIME: float = 0.25
const TRAIL_COLOR: Color = Color(2.0, 6.0, 8.0, 0.6)
const TRAIL_SHADER := preload("res://shaders/weapons/melee_trail.gdshader")
const TRAIL_DRIFT: float = 6.0
const TRAIL_SCALE_FADE: float = 0.55

enum Phase { NONE, PREP, ACTION, HOLD, RETURN }

var _is_swinging: bool = false
var _phase: int = Phase.NONE
var _phase_time: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _swing_dir: float = 1.0
var _swing_toggle: float = 1.0
var _facing_angle: float = 0.0
var _facing_sign: float = 1.0
var _visual_angle: float = NAN

var _pose_pos: Vector2 = Vector2.ZERO
var _pose_rot: float = 0.0
var _pose_scale: Vector2 = Vector2.ONE
var _from_pos: Vector2 = Vector2.ZERO
var _from_rot: float = 0.0
var _from_scale: Vector2 = Vector2.ONE

var _last_trail_angle: float = 0.0
var _pommel_offset: Vector2 = Vector2.ZERO


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
	_pommel_offset = _compute_pommel_offset(WEAPON_TEXTURE)
	_sprite.offset = _pommel_offset


static func _compute_pommel_offset(tex: Texture2D) -> Vector2:
	var tex_size := tex.get_size()
	# Sprite2D is centered by default: texture pixel p draws at (p - tex_size/2) + offset.
	# Solve for offset so POMMEL_PIXEL lands at the sprite origin.
	return tex_size * 0.5 - POMMEL_PIXEL


func _use_impl(user: Node) -> void:
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	var materials: Array[int] = MaterialTable.get_fluids()
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, 0.25, materials)
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
	var dir := _get_facing_direction(user)
	_facing_angle = dir.angle()
	if _visual_angle != _visual_angle:
		_visual_angle = _facing_angle
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, IDLE_ROTATION_SPEED * delta))
	_update_facing_sign(user, dir)
	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _update_facing_sign(user: Node, dir: Vector2) -> void:
	if user.has_method("is_facing_left"):
		_facing_sign = -1.0 if user.is_facing_left() else 1.0
		return
	if absf(dir.x) > 0.01:
		_facing_sign = signf(dir.x)
		return
	var c: float = cos(_facing_angle)
	if absf(c) > 0.01:
		_facing_sign = signf(c)


func _facing_unit() -> Vector2:
	return Vector2(cos(_facing_angle), sin(_facing_angle))


func _rest_pos() -> Vector2:
	return Vector2(_facing_sign * REST_FORWARD, REST_ABOVE)


func _rest_blade_angle() -> float:
	return _visual_angle


func _blade_to_sprite_rot(blade_angle: float) -> float:
	return blade_angle - LOCAL_BLADE_ANGLE


func _rest_rot() -> float:
	return _blade_to_sprite_rot(_rest_blade_angle())


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	if absf(direction.x) > 0.01:
		_facing_sign = signf(direction.x)
	_swing_toggle = -_swing_toggle
	_swing_dir = _swing_toggle
	_start_angle = _facing_angle - HALF_ARC * _swing_dir
	_end_angle = _facing_angle + HALF_ARC * _swing_dir
	_capture_from()
	_phase = Phase.PREP
	_phase_time = 0.0
	_last_trail_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
	_is_swinging = true


func _capture_from() -> void:
	_from_pos = _pose_pos
	_from_rot = _pose_rot
	_from_scale = _pose_scale


func _process_idle() -> void:
	_pose_pos = _rest_pos()
	_pose_rot = _rest_rot()
	_pose_scale = Vector2.ONE
	_apply_pose()


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
	return pow(2.0, -8.0 * x) * sin((x * 6.0 - 0.75) * C) + 1.0


func _process_swing(_delta: float) -> void:
	_phase_time += _delta

	var rest := _rest_pos()
	var facing := _facing_unit()
	var target_pos: Vector2 = rest
	var target_rot: float = 0.0
	var target_scale: Vector2 = Vector2.ONE
	var eased: float = 0.0
	var t: float = 0.0
	var blade_angle: float = 0.0

	match _phase:
		Phase.PREP:
			t = _phase_time / PREP_DURATION
			eased = _ease_out_quad(t)
			blade_angle = _start_angle - ANTICIPATION_PULLBACK * _swing_dir
			target_pos = rest - facing * PIVOT_BACK
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = PREP_SCALE
			if t >= 1.0:
				_pose_pos = target_pos
				_pose_rot = target_rot
				_pose_scale = target_scale
				_capture_from()
				_phase = Phase.ACTION
				_phase_time = 0.0
				_last_trail_angle = blade_angle
				_apply_pose()
				return

		Phase.ACTION:
			t = _phase_time / ACTION_DURATION
			eased = _ease_out_cubic(t)
			blade_angle = _end_angle + OVERSHOOT_ANGLE * _swing_dir
			target_pos = rest + facing * PIVOT_PUNCH
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = ACTION_SCALE
			if t >= 1.0:
				_pose_pos = target_pos
				_pose_rot = target_rot
				_pose_scale = target_scale
				_capture_from()
				_phase = Phase.HOLD
				_phase_time = 0.0
				_apply_pose()
				return

		Phase.HOLD:
			t = _phase_time / HOLD_DURATION
			eased = _ease_in_out_cubic(t)
			blade_angle = _end_angle
			target_pos = rest + facing * PIVOT_HOLD
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = HOLD_SCALE
			if t >= 1.0:
				_pose_pos = target_pos
				_pose_rot = target_rot
				_pose_scale = target_scale
				_capture_from()
				_phase = Phase.RETURN
				_phase_time = 0.0
				_apply_pose()
				return

		Phase.RETURN:
			t = _phase_time / RETURN_DURATION
			eased = _ease_out_elastic(t)
			target_pos = rest
			target_rot = _rest_rot()
			target_scale = Vector2.ONE
			if t >= 1.0:
				_is_swinging = false
				_process_idle()
				return

		_:
			_is_swinging = false
			_process_idle()
			return

	_pose_pos = _from_pos.lerp(target_pos, eased)
	_pose_rot = lerp_angle(_from_rot, target_rot, eased)
	_pose_scale = _from_scale.lerp(target_scale, eased)
	_apply_pose()

	if _phase == Phase.ACTION:
		var current_blade := _pose_rot + LOCAL_BLADE_ANGLE
		var progress := angle_difference(_last_trail_angle, current_blade) * _swing_dir
		var max_spawns := 32
		while progress >= TRAIL_ANGLE_STEP and max_spawns > 0:
			_last_trail_angle += TRAIL_ANGLE_STEP * _swing_dir
			progress -= TRAIL_ANGLE_STEP
			max_spawns -= 1
			_spawn_trail(_pose_pos, _last_trail_angle, _pose_scale)


func _apply_pose() -> void:
	visual.position = Vector2.ZERO
	visual.rotation = 0.0
	_sprite.position = _pose_pos
	_sprite.rotation = _pose_rot
	_sprite.scale = _pose_scale


func _spawn_trail(local_pos: Vector2, blade_angle: float, scale: Vector2) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TRAIL_SHADER
	var trail := Sprite2D.new()
	trail.texture = WEAPON_TEXTURE
	trail.offset = _pommel_offset
	trail.modulate = TRAIL_COLOR
	trail.material = mat
	trail.z_index = -1
	trail.z_as_relative = false
	visual.add_child(trail)
	trail.position = local_pos
	trail.rotation = _blade_to_sprite_rot(blade_angle)
	trail.scale = scale
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
