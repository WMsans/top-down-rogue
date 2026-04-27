class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var _last_facing: Vector2 = Vector2.DOWN
var _facing_left: bool = false

@onready var _color_rect: ColorRect = $ColorRect


func _ready() -> void:
	_color_rect.pivot_offset = Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	add_to_group("player")
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")
	var pickup_context := PickupContext.new()
	pickup_context.name = "PickupContext"
	add_child(pickup_context)
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = TerrainSurface.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)


func _physics_process(delta: float) -> void:
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

	var wm := get_parent().get_node_or_null("WorldManager")
	if wm:
		wm.tracking_position = global_position


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


func get_facing_direction() -> Vector2:
	return _last_facing


func is_facing_left() -> bool:
	return _facing_left
