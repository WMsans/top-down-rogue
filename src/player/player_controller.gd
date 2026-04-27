class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

const ShadowGridScript := preload("res://src/core/shadow_grid.gd")

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var shadow_grid: Node
var _last_facing: Vector2 = Vector2.DOWN
var _facing_left: bool = false

@onready var _color_rect: ColorRect = $ColorRect

@onready var _world_manager: Node2D = get_parent().get_node("WorldManager")


func _ready() -> void:
	_color_rect.pivot_offset = Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	add_to_group("player")
	collision_mask = 3
	shadow_grid = ShadowGridScript.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)

	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")

	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)
	shadow_grid.force_sync(Vector2i(position))


func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return

	var health_component := get_node_or_null("HealthComponent")
	if health_component and health_component.is_dead():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_dir := _get_input_direction()
	if input_dir != Vector2.ZERO:
		_last_facing = input_dir
		if input_dir.x < -0.01:
			_facing_left = true
		elif input_dir.x > 0.01:
			_facing_left = false
		if _color_rect != null:
			_color_rect.scale.x = -1.0 if _facing_left else 1.0
	_apply_movement(input_dir, delta)
	move_and_slide()

	_world_manager.tracking_position = global_position
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))


func _get_input_direction() -> Vector2:
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


func get_world_manager() -> Node:
	return _world_manager


func get_facing_direction() -> Vector2:
	return _last_facing


func is_facing_left() -> bool:
	return _facing_left
