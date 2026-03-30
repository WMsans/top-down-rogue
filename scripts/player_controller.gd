class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

const ShadowGridScript := preload("res://scripts/shadow_grid.gd")
const TerrainColliderScript := preload("res://scripts/terrain_collider.gd")

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var shadow_grid: Node
var _terrain_collider: StaticBody2D

@onready var _world_manager: Node2D = get_parent().get_node("WorldManager")


func _ready() -> void:
	# Create and configure the shadow grid
	shadow_grid = ShadowGridScript.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)
	shadow_grid.data_updated.connect(_on_terrain_data_updated)
	print("PlayerController: Connected to shadow_grid.data_updated signal")

	# Create terrain collider as sibling (child of Main)
	_terrain_collider = TerrainColliderScript.new()
	get_parent().call_deferred("add_child", _terrain_collider)
	print("PlayerController: Created TerrainCollider")
	print("  Player position: %s" % position)
	print("  Player collision_layer: %d" % collision_layer)
	print("  Player collision_mask: %d" % collision_mask)
	print("  TerrainCollider parent: %s" % _terrain_collider.get_parent())
	print("  TerrainCollider collision_layer: %d" % _terrain_collider.collision_layer)
	print("  TerrainCollider collision_mask: %d" % _terrain_collider.collision_mask)
	
	# Get collision shapes
	var player_shape = get_node("CollisionShape2D")
	if player_shape:
		print("  Player CollisionShape2D found, shape: %s" % player_shape.shape)
		if player_shape.shape:
			print("    Player shape size: %s" % player_shape.shape.size if player_shape.shape is RectangleShape2D else "N/A")

	# Wire world manager to track this player
	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	# Top-down movement: no floor/ceiling distinction
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	# Wait one frame for chunks to generate, then find spawn and sync
	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT / 2.0)
	shadow_grid.force_sync(Vector2i(position))


func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return
	
	print("=== Player._physics_process ===")
	print("  Player position: %s, global_position: %s" % [position, global_position])
	print("  Player velocity before input: %s" % velocity)
	
	var input_dir := _get_input_direction()
	print("  Input direction: %s" % input_dir)
	
	_apply_movement(input_dir, delta)
	print("  Velocity after movement: %s" % velocity)
	
	var velocity_before := velocity
	move_and_slide()
	var velocity_after := velocity
	
	print("  Velocity after move_and_slide: %s" % velocity_after)
	print("  Is on floor: %s, wall: %s" % [is_on_floor(), is_on_wall()])
	
	# Debug: Check if collision is happening
	if velocity_before.length_squared() > 0.001 and velocity_after.length_squared() < 0.001:
		print("  COLLISION DETECTED! Velocity cleared")
	elif velocity_before != velocity_after:
		print("  COLLISION DETECTED! Velocity changed from %s to %s" % [velocity_before, velocity_after])
	
	_world_manager.tracking_position = global_position
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))


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


func _on_terrain_data_updated() -> void:
	print("=== PlayerController._on_terrain_data_updated ===")
	if _terrain_collider == null:
		print("  ERROR: _terrain_collider is null!")
		return
	if shadow_grid == null:
		print("  ERROR: shadow_grid is null!")
		return
	
	print("  shadow_grid._anchor: %s" % shadow_grid._anchor)
	print("  shadow_grid.grid_size: %d" % shadow_grid.grid_size)
	print("  shadow_grid._data size: %d" % shadow_grid._data.size())
	
	_terrain_collider.rebuild(
		shadow_grid._data,
		shadow_grid._anchor,
		shadow_grid.grid_size
	)
