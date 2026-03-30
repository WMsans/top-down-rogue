class_name PlayerController
extends Node2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

const ShadowGridScript := preload("res://scripts/shadow_grid.gd")

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var velocity: Vector2 = Vector2.ZERO
var shadow_grid: Node

@onready var _world_manager: Node2D = get_parent().get_node("WorldManager")

## Collision state — available for gameplay mechanics.
var is_on_floor: bool = false
var is_on_wall_left: bool = false
var is_on_wall_right: bool = false
var is_on_ceiling: bool = false


func _ready() -> void:
	# Create and configure the shadow grid
	shadow_grid = ShadowGridScript.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)

	# Wire world manager to track this player
	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	# Wait one frame for chunks to generate, then find spawn and sync
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	shadow_grid.force_sync(Vector2i(position))


func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return
	var input_dir := _get_input_direction()
	_apply_movement(input_dir, delta)
	_move_and_collide(delta)
	_update_contact_state()


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
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


func _move_and_collide(delta: float) -> void:
	var half_w: float = float(BODY_WIDTH) / 2.0
	var half_h: float = float(BODY_HEIGHT) / 2.0
	var body_top: int = int(floor(position.y - half_h + 0.0001))

	var new_x: float = position.x + velocity.x * delta
	if velocity.x > 0:
		var start_edge: float = position.x + half_w
		var end_edge: float = new_x + half_w
		var start_pixel: int = int(ceil(start_edge - 0.0001))
		var end_pixel: int = int(ceil(end_edge - 0.0001))
		for px in range(start_pixel, end_pixel + 1):
			if _column_has_solid(px, body_top, BODY_HEIGHT):
				new_x = float(px) - half_w - 0.0001
				velocity.x = 0
				break
	elif velocity.x < 0:
		var start_edge: float = position.x - half_w
		var end_edge: float = new_x - half_w
		var start_pixel: int = int(start_edge - 0.0001)
		var end_pixel: int = int(end_edge - 0.0001)
		for px in range(start_pixel, end_pixel - 1, -1):
			if _column_has_solid(px, body_top, BODY_HEIGHT):
				new_x = float(px) + 1.0 + half_w
				velocity.x = 0
				break

	var body_left: int = int(floor(new_x - half_w + 0.0001))
	var new_y: float = position.y + velocity.y * delta
	if velocity.y > 0:
		var start_edge: float = position.y + half_h
		var end_edge: float = new_y + half_h
		var start_pixel: int = int(ceil(start_edge - 0.0001))
		var end_pixel: int = int(ceil(end_edge - 0.0001))
		for py in range(start_pixel, end_pixel + 1):
			if _row_has_solid(body_left, py, BODY_WIDTH):
				new_y = float(py) - half_h - 0.0001
				velocity.y = 0
				break
	elif velocity.y < 0:
		var start_edge: float = position.y - half_h
		var end_edge: float = new_y - half_h
		var start_pixel: int = int(start_edge - 0.0001)
		var end_pixel: int = int(end_edge - 0.0001)
		for py in range(start_pixel, end_pixel - 1, -1):
			if _row_has_solid(body_left, py, BODY_WIDTH):
				new_y = float(py) + 1.0 + half_h
				velocity.y = 0
				break

	position = Vector2(new_x, new_y)


## Check if any pixel in a vertical column is solid.
func _column_has_solid(world_x: int, world_y_start: int, height: int) -> bool:
	for y in range(world_y_start, world_y_start + height):
		if shadow_grid.is_solid(world_x, y):
			return true
	return false


## Check if any pixel in a horizontal row is solid.
func _row_has_solid(world_x_start: int, world_y: int, width: int) -> bool:
	for x in range(world_x_start, world_x_start + width):
		if shadow_grid.is_solid(x, world_y):
			return true
	return false


## Sample adjacent pixels for contact state (available for future gameplay).
func _update_contact_state() -> void:
	var half_w: float = float(BODY_WIDTH) / 2.0
	var half_h: float = float(BODY_HEIGHT) / 2.0
	var body_left: int = int(floor(position.x - half_w + 0.0001))
	var body_top: int = int(floor(position.y - half_h + 0.0001))

	is_on_floor = _row_has_solid(body_left, body_top + BODY_HEIGHT, BODY_WIDTH)
	is_on_ceiling = _row_has_solid(body_left, body_top - 1, BODY_WIDTH)
	is_on_wall_left = _column_has_solid(body_left - 1, body_top, BODY_HEIGHT)
	is_on_wall_right = _column_has_solid(body_left + BODY_WIDTH, body_top, BODY_HEIGHT)

	_world_manager.tracking_position = global_position
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))
