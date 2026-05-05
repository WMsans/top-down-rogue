class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var _last_facing: Vector2 = Vector2.DOWN
var _facing_left: bool = false
var _original_collision_layer: int
var _original_collision_mask: int

@onready var _color_rect: ColorRect = $ColorRect

const KNOCKBACK_SPEED := 20.0
const KNOCKBACK_DECAY := 12.0
const ZOOM_PUNCH_THRESHOLD := 10.0
const ZOOM_PUNCH_AMOUNT := 0.92
const HIT_FLASH_COLOR := Color(2.5, 0.3, 0.1)

var _knockback_velocity: Vector2 = Vector2.ZERO
var _flash_tween: Tween
var _squash_tween: Tween
var _zoom_tween: Tween


func _enter_tree() -> void:
	var inventory := PlayerInventory.new()
	inventory.name = "PlayerInventory"
	add_child(inventory)

func _ready() -> void:
	_color_rect.pivot_offset = Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	add_to_group("player")
	collision_mask = 3
	collision_layer = 1
	_original_collision_layer = collision_layer
	_original_collision_mask = collision_mask
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")
	var pickup_context := PickupContext.new()
	pickup_context.name = "PickupContext"
	add_child(pickup_context)
	var delivery := WeaponDelivery.new()
	delivery.name = "WeaponDelivery"
	add_child(delivery)
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = TerrainSurface.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)


func _physics_process(delta: float) -> void:
	var inventory := get_node_or_null("PlayerInventory")
	if GameModeManager.is_creative():
		collision_layer = 0
		collision_mask = 0
	else:
		collision_layer = _original_collision_layer
		collision_mask = _original_collision_mask
	if inventory and inventory.is_dead():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := _get_input_direction()
	if _knockback_velocity.length_squared() > 0.01:
		_knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)
	if input_dir != Vector2.ZERO:
		_last_facing = input_dir
		if input_dir.x < -0.01:
			_facing_left = true
		elif input_dir.x > 0.01:
			_facing_left = false
		if _color_rect != null:
			_color_rect.scale.x = -1.0 if _facing_left else 1.0
	_apply_movement(input_dir, delta)
	velocity += _knockback_velocity
	move_and_slide()

	var wm := get_parent().get_node_or_null("WorldManager")
	if wm:
		wm.tracking_position = global_position


func _get_input_direction() -> Vector2:
	if ConsoleManager.is_open():
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	return dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO


func _apply_movement(input_dir: Vector2, delta: float) -> void:
	if input_dir != Vector2.ZERO:
		velocity += input_dir * acceleration * delta
	else:
		var friction_amount: float = friction * delta
		if velocity.length() <= friction_amount:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity.normalized() * friction_amount
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed


func get_facing_direction() -> Vector2:
	return _last_facing


func is_facing_left() -> bool:
	return _facing_left


func on_hit_impact(impact_point: Vector2, hit_dir: Vector2, damage: int) -> void:
	if hit_dir.length_squared() > 0.0001:
		_knockback_velocity = hit_dir.normalized() * KNOCKBACK_SPEED

	_play_hit_flash()
	_play_squash()
	_play_zoom_punch(damage)

	var inventory := get_node_or_null("PlayerInventory")
	if inventory:
		inventory.take_damage(damage, hit_dir)


func _play_hit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_color_rect.modulate = HIT_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_color_rect, "modulate", Color.WHITE, 0.12)


func _play_squash() -> void:
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	var sgn := -1.0 if _facing_left else 1.0
	var target_scale := Vector2(sgn * 1.3, 0.7)
	var rest_scale := Vector2(sgn, 1.0)
	_squash_tween = create_tween()
	_squash_tween.tween_property(_color_rect, "scale", target_scale, 0.06)
	_squash_tween.tween_property(_color_rect, "scale", rest_scale, 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _play_zoom_punch(damage: int) -> void:
	if damage < ZOOM_PUNCH_THRESHOLD:
		return
	var cam := get_node_or_null("Camera2D")
	if cam == null:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var default_zoom : Vector2 = cam.zoom
	var punched_zoom := default_zoom * ZOOM_PUNCH_AMOUNT
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(cam, "zoom", punched_zoom, 0.07).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_property(cam, "zoom", default_zoom, 0.08)
