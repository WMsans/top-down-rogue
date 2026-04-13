class_name MeleeWeapon
extends Weapon

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const RANGE: float = 40.0
const ARC_ANGLE: float = PI / 2.0
const COOLDOWN: float = 0.5
const PUSH_SPEED: float = 60.0

# Visual constants
const PIVOT_DISTANCE: float = 15.0
const SWING_DURATION: float = 0.30
const HALF_ARC: float = PI / 3.5

# Phase timing ratios
const PREP_END: float = 0.12
const ACTION_END: float = 0.32
const SETTLE_END: float = 0.60
const RETURN_START: float = 0.60
const RETURN_EASE_POWER: float = 2.5

# Swing angles
const ANTICIPATION_PULLBACK: float = PI / 6.0
const OVERSHOOT_ANGLE: float = PI / 5.0
const SETTLE_BOUNCE_AMOUNT: float = PI / 14.0

# Squash & stretch
const PREP_SCALE: Vector2 = Vector2(1.25, 0.75)
const ACTION_SCALE: Vector2 = Vector2(0.7, 1.35)
const SETTLE_SCALE: Vector2 = Vector2(1.1, 0.92)

# Distance punch
const PUNCH_DISTANCE: float = 22.0

# Trail
const TRAIL_INTERVAL: float = 0.02
const TRAIL_LIFETIME: float = 0.15
const TRAIL_COLOR: Color = Color(0.3, 0.9, 1.0, 0.6)

var _cooldown_timer: float = 0.0
var _is_swinging: bool = false
var _elapsed: float = 0.0
var _start_angle: float = 0.0
var _end_angle: float = 0.0
var _facing_angle: float = 0.0
var _visual_angle: float = NAN
var _trail_timer: float = 0.0

const IDLE_ROTATION_SPEED: float = 10.0


func _init() -> void:
	name = "Melee Weapon"


func has_visual() -> bool:
	return true


func setup_visual(container: Node2D, sprite: Sprite2D) -> void:
	super.setup_visual(container, sprite)
	_sprite.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	_sprite.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)


func use(user: Node) -> void:
	if _cooldown_timer > 0.0:
		return

	var world_manager := _get_world_manager(user)
	if world_manager == null:
		return

	var pos: Vector2 = user.global_position
	var direction := _get_facing_direction(user)

	_start_swing(direction)

	var materials: Array[int] = [
		MaterialRegistry.MAT_GAS,
		MaterialRegistry.MAT_LAVA
	]
	world_manager.disperse_materials_in_arc(pos, direction, RANGE, ARC_ANGLE, PUSH_SPEED, materials)

	_cooldown_timer = COOLDOWN


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

	if _is_swinging:
		_process_swing(delta)
	else:
		_process_idle()


func _start_swing(direction: Vector2) -> void:
	_facing_angle = direction.angle()
	_start_angle = _facing_angle - HALF_ARC
	_end_angle = _facing_angle + HALF_ARC
	_elapsed = 0.0
	_trail_timer = TRAIL_INTERVAL
	_is_swinging = true


func _process_idle() -> void:
	visual.position = Vector2(cos(_visual_angle), sin(_visual_angle)) * PIVOT_DISTANCE
	visual.rotation = _visual_angle + PI / 2.0
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE


func _process_swing(delta: float) -> void:
	_elapsed += delta
	_trail_timer += delta

	var t := _elapsed / SWING_DURATION
	if t >= 1.0:
		_is_swinging = false
		_process_idle()
		return

	visual.position = Vector2.ZERO
	visual.rotation = 0.0

	var current_angle := _get_swing_angle(t)
	var dist := _get_swing_distance(t)
	_sprite.position = Vector2(cos(current_angle), sin(current_angle)) * dist
	_sprite.rotation = current_angle + PI / 2.0
	_sprite.scale = _get_swing_scale(t)

	var interval := TRAIL_INTERVAL * (0.5 if t >= PREP_END and t < ACTION_END else 1.0)
	if _trail_timer >= interval:
		_trail_timer -= interval
		_spawn_trail()


func _get_swing_angle(t: float) -> float:
	var swing_dir := signf(_end_angle - _start_angle)

	if t < PREP_END:
		var prep_t := t / PREP_END
		var eased := _ease_out_quad(prep_t)
		var pullback_target := _start_angle - ANTICIPATION_PULLBACK * swing_dir
		return lerpf(_start_angle, pullback_target, eased)

	elif t < ACTION_END:
		var action_t := (t - PREP_END) / (ACTION_END - PREP_END)
		var eased := _ease_in_out_cubic(action_t)
		var pullback_angle := _start_angle - ANTICIPATION_PULLBACK * swing_dir
		var overshoot_target := _end_angle + OVERSHOOT_ANGLE * swing_dir
		return lerpf(pullback_angle, overshoot_target, eased)

	elif t < SETTLE_END:
		var settle_t := (t - ACTION_END) / (SETTLE_END - ACTION_END)
		var overshoot_target := _end_angle + OVERSHOOT_ANGLE * swing_dir
		var base := lerpf(overshoot_target, _end_angle, _ease_out_quad(settle_t))
		var bounce := sin(settle_t * PI * 3.0) * SETTLE_BOUNCE_AMOUNT * (1.0 - settle_t)
		return base + bounce * swing_dir

	else:
		var return_t := (t - RETURN_START) / (1.0 - RETURN_START)
		var eased_return := ease(return_t, RETURN_EASE_POWER)
		return lerpf(_end_angle, _facing_angle, eased_return)


func _get_swing_distance(t: float) -> float:
	if t < PREP_END:
		var prep_t := t / PREP_END
		return lerpf(PIVOT_DISTANCE, PIVOT_DISTANCE * 0.85, _ease_out_quad(prep_t))
	elif t < ACTION_END:
		var action_t := (t - PREP_END) / (ACTION_END - PREP_END)
		var punch := sin(action_t * PI)
		return lerpf(PIVOT_DISTANCE * 0.85, PIVOT_DISTANCE, action_t) + punch * (PUNCH_DISTANCE - PIVOT_DISTANCE)
	else:
		return PIVOT_DISTANCE


func _get_swing_scale(t: float) -> Vector2:
	if t < PREP_END:
		var prep_t := t / PREP_END
		return Vector2.ONE.lerp(PREP_SCALE, _ease_out_quad(prep_t))
	elif t < ACTION_END:
		var action_t := (t - PREP_END) / (ACTION_END - PREP_END)
		if action_t < 0.5:
			return PREP_SCALE.lerp(ACTION_SCALE, _ease_in_out_cubic(action_t * 2.0))
		else:
			return ACTION_SCALE.lerp(Vector2.ONE, _ease_out_quad((action_t - 0.5) * 2.0))
	elif t < SETTLE_END:
		var settle_t := (t - ACTION_END) / (SETTLE_END - ACTION_END)
		return Vector2.ONE.lerp(SETTLE_SCALE, (1.0 - settle_t) * sin(settle_t * PI))
	else:
		return Vector2.ONE


func _spawn_trail() -> void:
	var trail := Sprite2D.new()
	trail.texture = WEAPON_TEXTURE
	var tex_size := WEAPON_TEXTURE.get_size()
	trail.offset = Vector2(tex_size.x / 2.0, -tex_size.y / 4.0)
	trail.modulate = TRAIL_COLOR
	visual.get_tree().current_scene.add_child(trail)
	trail.global_position = _sprite.global_position
	trail.global_rotation = _sprite.global_rotation
	var tween := trail.create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, TRAIL_LIFETIME)
	tween.tween_callback(trail.queue_free)


func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var f := -2.0 * t + 2.0
		return 1.0 - f * f * f / 2.0


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
