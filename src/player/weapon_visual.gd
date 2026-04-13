class_name WeaponVisual
extends Node2D

const WEAPON_TEXTURE := preload("res://textures/weapon.png")
const PIVOT_DISTANCE: float = 15.0

const SWING_DURATION: float = 0.30
const HALF_ARC: float = PI / 3.5

# Phase timing ratios (must sum to ~SWING_PHASE_END)
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

# Distance punch (weapon lunges forward during action)
const PUNCH_DISTANCE: float = 22.0

# Trail
const TRAIL_INTERVAL: float = 0.02
const TRAIL_LIFETIME: float = 0.15
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
	_sprite.scale = Vector2.ONE


func _process_swing(delta: float) -> void:
	_elapsed += delta
	_trail_timer += delta

	var t := _elapsed / SWING_DURATION
	if t >= 1.0:
		_is_swinging = false
		_sprite.position = Vector2.ZERO
		_sprite.rotation = 0.0
		_sprite.scale = Vector2.ONE
		_process_idle()
		return

	position = Vector2.ZERO
	rotation = 0.0

	var current_angle := _get_swing_angle(t)
	var dist := _get_swing_distance(t)
	_sprite.position = _get_position_at_angle(current_angle, dist)
	_sprite.rotation = current_angle + PI / 2.0
	_sprite.scale = _get_swing_scale(t)

	# Spawn trails more aggressively during action phase
	var interval := TRAIL_INTERVAL * (0.5 if t >= PREP_END and t < ACTION_END else 1.0)
	if _trail_timer >= interval:
		_trail_timer -= interval
		_spawn_trail()


func _get_swing_angle(t: float) -> float:
	var swing_dir := signf(_end_angle - _start_angle)

	if t < PREP_END:
		# Anticipation: pull back behind the start angle
		var prep_t := t / PREP_END
		var eased := _ease_out_quad(prep_t)
		var pullback_target := _start_angle - ANTICIPATION_PULLBACK * swing_dir
		return lerpf(_start_angle, pullback_target, eased)

	elif t < ACTION_END:
		# Action: fast swing from pullback through to overshoot
		var action_t := (t - PREP_END) / (ACTION_END - PREP_END)
		var eased := _ease_in_out_cubic(action_t)
		var pullback_angle := _start_angle - ANTICIPATION_PULLBACK * swing_dir
		var overshoot_target := _end_angle + OVERSHOOT_ANGLE * swing_dir
		return lerpf(pullback_angle, overshoot_target, eased)

	elif t < SETTLE_END:
		# Settle: damped bounce around end angle
		var settle_t := (t - ACTION_END) / (SETTLE_END - ACTION_END)
		var overshoot_target := _end_angle + OVERSHOOT_ANGLE * swing_dir
		var base := lerpf(overshoot_target, _end_angle, _ease_out_quad(settle_t))
		var bounce := sin(settle_t * PI * 3.0) * SETTLE_BOUNCE_AMOUNT * (1.0 - settle_t)
		return base + bounce * swing_dir

	else:
		# Return: ease back to facing (preserved from original)
		var return_t := (t - RETURN_START) / (1.0 - RETURN_START)
		var eased_return := ease(return_t, RETURN_EASE_POWER)
		return lerpf(_end_angle, _facing_angle, eased_return)


func _get_swing_distance(t: float) -> float:
	if t < PREP_END:
		# Pull in slightly during anticipation
		var prep_t := t / PREP_END
		return lerpf(PIVOT_DISTANCE, PIVOT_DISTANCE * 0.85, _ease_out_quad(prep_t))
	elif t < ACTION_END:
		# Punch forward during action
		var action_t := (t - PREP_END) / (ACTION_END - PREP_END)
		var punch := sin(action_t * PI) # peaks at midpoint
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


func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


func _ease_in_out_cubic(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var f := -2.0 * t + 2.0
		return 1.0 - f * f * f / 2.0


func _get_player() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.has_method("get_facing_direction"):
		return parent
	return null