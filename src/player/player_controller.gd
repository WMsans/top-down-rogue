class_name PlayerController
extends CharacterBody2D

const BODY_WIDTH := 8
const BODY_HEIGHT := 12

const ShadowGridScript := preload("res://src/core/shadow_grid.gd")
const TestWeaponScript := preload("res://src/weapons/test_weapon.gd")

@export var acceleration: float = 800.0
@export var friction: float = 600.0
@export var max_speed: float = 120.0

var weapons: Array[Weapon] = []
var shadow_grid: Node
var _last_facing: Vector2 = Vector2.DOWN

@onready var _world_manager: Node2D = get_parent().get_node("WorldManager")


func _ready() -> void:
	shadow_grid = ShadowGridScript.new()
	shadow_grid.world_manager = _world_manager
	add_child(shadow_grid)

	_world_manager.tracking_position = global_position
	_world_manager.shadow_grid = shadow_grid

	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("gas_interactors")

	weapons.resize(3)
	weapons[0] = TestWeaponScript.new()

	await get_tree().process_frame
	await get_tree().process_frame
	var spawn_pos: Vector2i = _world_manager.find_spawn_position(Vector2i.ZERO, Vector2i(BODY_WIDTH, BODY_HEIGHT))
	position = Vector2(spawn_pos) + Vector2(BODY_WIDTH / 2.0, BODY_HEIGHT)
	shadow_grid.force_sync(Vector2i(position))


func _physics_process(delta: float) -> void:
	if shadow_grid == null:
		return

	var input_dir := _get_input_direction()
	_apply_movement(input_dir, delta)
	move_and_slide()

	_world_manager.tracking_position = global_position
	shadow_grid.update_sync(Vector2i(int(floor(position.x)), int(floor(position.y))))
	_tick_weapons(delta)


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := -1
		match event.keycode:
			KEY_Z: slot = 0
			KEY_X: slot = 1
			KEY_C: slot = 2
		if slot >= 0 and slot < weapons.size() and weapons[slot] != null:
			weapons[slot].use(self)


func _tick_weapons(delta: float) -> void:
	for weapon in weapons:
		if weapon != null and weapon.has_method("tick"):
			weapon.tick(delta)


func get_world_manager() -> Node:
	return _world_manager


func get_facing_direction() -> Vector2:
	if velocity.length_squared() > 0.01:
		_last_facing = velocity.normalized()
	return _last_facing
