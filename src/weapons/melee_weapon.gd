class_name MeleeWeapon
extends Weapon

@export var weapon_texture: Texture2D = preload("res://textures/Weapons/sword_01c.png")
@export var weapon_reach: float = 36.0
@export var arc_angle: float = PI / 2.0
@export var push_speed: float = 60.0

# Sprite is 18x18 with pommel at (15, 15) and blade pointing top-left.
# Shift the texture so the pommel sits at the sprite origin (the rotation pivot),
# and remember the blade's local direction at rotation=0 for converting blade
# angles into sprite rotations.
@export var pommel_pixel: Vector2 = Vector2(15.0, 15.0)
@export var local_blade_angle: float = -3.0 * PI / 4.0
@export var half_arc: float = PI / 3.5
@export var idle_rotation_speed: float = 10.0

@export var prep_duration: float = 0.06
@export var action_duration: float = 0.09
@export var hold_duration: float = 0.025
@export var return_duration: float = 0.32

@export var anticipation_pullback: float = PI / 5.0
@export var overshoot_angle: float = PI / 9.0

@export var prep_scale: Vector2 = Vector2(1.25, 0.75)
@export var action_scale: Vector2 = Vector2(0.7, 1.35)
@export var hold_scale: Vector2 = Vector2(1.05, 0.95)

# Pommel rests above the player body; small forward shifts drive the swing's
# weight transfer while the blade rotation does the visible work.
@export var rest_above: float = 0.0
@export var rest_forward: float = 3.0
@export var pivot_back: float = 2.0
@export var pivot_punch: float = 4.0
@export var pivot_hold: float = 3.0

@export var trail_angle_step: float = PI / 32.0
@export var trail_lifetime: float = 0.25
@export var trail_color: Color = Color(2.0, 6.0, 8.0, 0.6)
@export var trail_shader: Shader = preload("res://shaders/weapons/melee_trail.gdshader")
@export var trail_drift: float = 6.0
@export var trail_scale_fade: float = 0.55

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
	cooldown = 0.35
	damage = 5.0
	icon_texture = weapon_texture
	modifier_slot_count = 3
	modifiers.resize(modifier_slot_count)


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = weapon_texture
	_pommel_offset = _compute_pommel_offset(weapon_texture)
	_sprite.offset = _pommel_offset


func _compute_pommel_offset(tex: Texture2D) -> Vector2:
	var tex_size := tex.get_size()
	# Sprite2D is centered by default: texture pixel p draws at (p - tex_size/2) + offset.
	# Solve for offset so pommel_pixel lands at the sprite origin.
	return tex_size * 0.5 - pommel_pixel


func _use_impl(user: Node) -> void:
	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)
	_start_swing(direction)
	# Push fluids (gas, lava) — existing behavior, no hardness
	var fluids: Array[int] = MaterialRegistry.get_fluids()
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, push_speed, 0.25, fluids)
	# Carve solids (wall materials) — new, with hardness scaling
	var solids: Array[int] = [
		MaterialRegistry.MAT_DIRT,
		MaterialRegistry.MAT_WOOD,
		MaterialRegistry.MAT_STONE,
		MaterialRegistry.MAT_COAL,
		MaterialRegistry.MAT_ICE,
	]
	TerrainSurface.clear_and_push_materials_in_arc(pos, direction, weapon_reach, arc_angle, 0.0, 0.0, solids, damage)
	_hit_attackables_in_arc(user, pos, direction)


func _hit_attackables_in_arc(user: Node, origin: Vector2, direction: Vector2) -> void:
	var dmg: int = int(damage)
	if dmg <= 0:
		return
	var dir_angle: float = direction.angle()
	var half_arc_angle: float = arc_angle / 2.0
	for node in user.get_tree().get_nodes_in_group("attackable"):
		if not (node is Node2D):
			continue
		if not node.has_method("on_hit_impact"):
			continue
		var to_target: Vector2 = node.global_position - origin
		var dist: float = to_target.length()
		if dist > weapon_reach or dist <= 0.001:
			continue
		if absf(angle_difference(dir_angle, to_target.angle())) > half_arc_angle:
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
	_visual_angle = lerp_angle(_visual_angle, _facing_angle, minf(1.0, idle_rotation_speed * delta))
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
	return Vector2(_facing_sign * rest_forward, rest_above)


func _rest_blade_angle() -> float:
	return _visual_angle


func _blade_to_sprite_rot(blade_angle: float) -> float:
	return blade_angle - local_blade_angle


func _rest_rot() -> float:
	return _blade_to_sprite_rot(_rest_blade_angle())


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	if absf(direction.x) > 0.01:
		_facing_sign = signf(direction.x)
	_swing_toggle = -_swing_toggle
	_swing_dir = _swing_toggle
	_start_angle = _facing_angle - half_arc * _swing_dir
	_end_angle = _facing_angle + half_arc * _swing_dir
	_capture_from()
	_phase = Phase.PREP
	_phase_time = 0.0
	_last_trail_angle = _start_angle - anticipation_pullback * _swing_dir
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
			t = _phase_time / prep_duration
			eased = _ease_out_quad(t)
			blade_angle = _start_angle - anticipation_pullback * _swing_dir
			target_pos = rest - facing * pivot_back
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = prep_scale
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
			t = _phase_time / action_duration
			eased = _ease_out_cubic(t)
			blade_angle = _end_angle + overshoot_angle * _swing_dir
			target_pos = rest + facing * pivot_punch
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = action_scale
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
			t = _phase_time / hold_duration
			eased = _ease_in_out_cubic(t)
			blade_angle = _end_angle
			target_pos = rest + facing * pivot_hold
			target_rot = _blade_to_sprite_rot(blade_angle)
			target_scale = hold_scale
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
			t = _phase_time / return_duration
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
		var current_blade := _pose_rot + local_blade_angle
		var progress := angle_difference(_last_trail_angle, current_blade) * _swing_dir
		var max_spawns := 32
		while progress >= trail_angle_step and max_spawns > 0:
			_last_trail_angle += trail_angle_step * _swing_dir
			progress -= trail_angle_step
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
	mat.shader = trail_shader
	var trail := Sprite2D.new()
	trail.texture = weapon_texture
	trail.offset = _pommel_offset
	trail.modulate = trail_color
	trail.material = mat
	trail.z_index = -1
	trail.z_as_relative = false
	visual.add_child(trail)
	trail.position = local_pos
	trail.rotation = _blade_to_sprite_rot(blade_angle)
	trail.scale = scale
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, trail_lifetime)
	tween.tween_callback(trail.queue_free)


func _get_facing_direction(user: Node) -> Vector2:
	if user.has_method("get_facing_direction"):
		return user.get_facing_direction()
	if "velocity" in user:
		var vel = user.get("velocity")
		if vel is Vector2 and vel.length_squared() > 0.01:
			return vel.normalized()
	return Vector2.DOWN
